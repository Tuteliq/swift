import Foundation

// MARK: - Voice Stream Types

/// Configuration for a voice streaming session.
public struct VoiceStreamConfig: Sendable {
    /// Flush interval in seconds (5–30, default 10).
    public var intervalSeconds: Int?
    /// Analysis types to run on each flush.
    public var analysisTypes: [String]?
    /// Additional context for analysis.
    public var context: AnalysisContext?

    public init(
        intervalSeconds: Int? = nil,
        analysisTypes: [String]? = nil,
        context: AnalysisContext? = nil
    ) {
        self.intervalSeconds = intervalSeconds
        self.analysisTypes = analysisTypes
        self.context = context
    }
}

// MARK: - Server → Client Events

/// Emitted when the session is ready.
public struct VoiceReadyEvent: Sendable {
    public let sessionId: String
    public let config: [String: Any]

    init(data: [String: Any]) {
        sessionId = data["session_id"] as? String ?? ""
        config = data["config"] as? [String: Any] ?? [:]
    }
}

/// A segment of transcribed audio.
public struct VoiceTranscriptionSegment: Sendable {
    public let start: Double
    public let end: Double
    public let text: String
}

/// Emitted when a transcription flush arrives.
public struct VoiceTranscriptionEvent: Sendable {
    public let text: String
    public let segments: [VoiceTranscriptionSegment]
    public let flushIndex: Int

    init(data: [String: Any]) {
        text = data["text"] as? String ?? ""
        flushIndex = data["flush_index"] as? Int ?? 0
        let rawSegments = data["segments"] as? [[String: Any]] ?? []
        segments = rawSegments.map {
            VoiceTranscriptionSegment(
                start: $0["start"] as? Double ?? 0,
                end: $0["end"] as? Double ?? 0,
                text: $0["text"] as? String ?? ""
            )
        }
    }
}

/// Emitted when a safety alert is triggered.
public struct VoiceAlertEvent: Sendable {
    public let category: String
    public let severity: String
    public let riskScore: Double
    public let details: [String: Any]
    public let flushIndex: Int

    init(data: [String: Any]) {
        category = data["category"] as? String ?? ""
        severity = data["severity"] as? String ?? ""
        riskScore = data["risk_score"] as? Double ?? 0
        details = data["details"] as? [String: Any] ?? [:]
        flushIndex = data["flush_index"] as? Int ?? 0
    }
}

/// Emitted when the session ends with a summary.
public struct VoiceSessionSummaryEvent: Sendable {
    public let sessionId: String
    public let durationSeconds: Double
    public let overallRisk: String
    public let overallRiskScore: Double
    public let totalFlushes: Int
    public let transcript: String

    init(data: [String: Any]) {
        sessionId = data["session_id"] as? String ?? ""
        durationSeconds = data["duration_seconds"] as? Double ?? 0
        overallRisk = data["overall_risk"] as? String ?? ""
        overallRiskScore = data["overall_risk_score"] as? Double ?? 0
        totalFlushes = data["total_flushes"] as? Int ?? 0
        transcript = data["transcript"] as? String ?? ""
    }
}

/// Emitted when config is updated.
public struct VoiceConfigUpdatedEvent: Sendable {
    public let config: [String: Any]

    init(data: [String: Any]) {
        config = data["config"] as? [String: Any] ?? [:]
    }
}

/// Emitted on server-side errors.
public struct VoiceErrorEvent: Sendable {
    public let code: String
    public let message: String

    init(data: [String: Any]) {
        code = data["code"] as? String ?? ""
        message = data["message"] as? String ?? ""
    }
}

// MARK: - Handler Callbacks

/// Callback handlers for voice stream events.
public struct VoiceStreamHandlers: Sendable {
    public var onReady: (@Sendable (VoiceReadyEvent) -> Void)?
    public var onTranscription: (@Sendable (VoiceTranscriptionEvent) -> Void)?
    public var onAlert: (@Sendable (VoiceAlertEvent) -> Void)?
    public var onSessionSummary: (@Sendable (VoiceSessionSummaryEvent) -> Void)?
    public var onConfigUpdated: (@Sendable (VoiceConfigUpdatedEvent) -> Void)?
    public var onError: (@Sendable (VoiceErrorEvent) -> Void)?
    public var onClose: (@Sendable (URLSessionWebSocketTask.CloseCode, String?) -> Void)?

    public init(
        onReady: (@Sendable (VoiceReadyEvent) -> Void)? = nil,
        onTranscription: (@Sendable (VoiceTranscriptionEvent) -> Void)? = nil,
        onAlert: (@Sendable (VoiceAlertEvent) -> Void)? = nil,
        onSessionSummary: (@Sendable (VoiceSessionSummaryEvent) -> Void)? = nil,
        onConfigUpdated: (@Sendable (VoiceConfigUpdatedEvent) -> Void)? = nil,
        onError: (@Sendable (VoiceErrorEvent) -> Void)? = nil,
        onClose: (@Sendable (URLSessionWebSocketTask.CloseCode, String?) -> Void)? = nil
    ) {
        self.onReady = onReady
        self.onTranscription = onTranscription
        self.onAlert = onAlert
        self.onSessionSummary = onSessionSummary
        self.onConfigUpdated = onConfigUpdated
        self.onError = onError
        self.onClose = onClose
    }
}

// MARK: - Voice Stream Session

/// A voice streaming session over WebSocket.
///
/// Uses `URLSessionWebSocketTask` (no external dependencies).
///
/// ```swift
/// let session = tuteliq.voiceStream(
///     config: VoiceStreamConfig(intervalSeconds: 10, analysisTypes: ["bullying", "unsafe"]),
///     handlers: VoiceStreamHandlers(
///         onTranscription: { print("Transcript:", $0.text) },
///         onAlert: { print("Alert:", $0.category, $0.severity) }
///     )
/// )
///
/// try await session.connect()
/// try session.sendAudio(audioData)
/// let summary = try await session.end()
/// print("Risk:", summary.overallRisk)
/// ```
public final class VoiceStreamSession: @unchecked Sendable {
    private let apiKey: String
    private let config: VoiceStreamConfig?
    private let handlers: VoiceStreamHandlers
    private let baseURL: String

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var _sessionId: String?
    private var _isActive = false
    private let lock = NSLock()

    private var summaryContinuation: CheckedContinuation<VoiceSessionSummaryEvent, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?

    /// The session ID (available after ready event).
    public var sessionId: String? {
        lock.lock()
        defer { lock.unlock() }
        return _sessionId
    }

    /// Whether the connection is active.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }

    init(
        apiKey: String,
        config: VoiceStreamConfig? = nil,
        handlers: VoiceStreamHandlers = VoiceStreamHandlers(),
        baseURL: String = "wss://api.tuteliq.ai/voice/stream"
    ) {
        self.apiKey = apiKey
        self.config = config
        self.handlers = handlers
        self.baseURL = baseURL
    }

    /// Open the WebSocket connection and wait for the ready event.
    public func connect() async throws {
        guard let url = URL(string: baseURL) else {
            throw TuteliqError.validationError("Invalid voice stream URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let urlSession = URLSession(configuration: .default)
        let ws = urlSession.webSocketTask(with: request)
        session = urlSession
        webSocket = ws
        ws.resume()

        lock.lock()
        _isActive = true
        lock.unlock()

        // Send initial config
        if let config = config {
            try await sendConfig(config)
        }

        // Wait for ready event
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.readyContinuation = continuation
            lock.unlock()
            listenForMessages()
        }
    }

    /// Send raw audio data (binary frame).
    public func sendAudio(_ data: Data) throws {
        guard let ws = webSocket, isActive else {
            throw TuteliqError.validationError("Voice stream is not connected")
        }
        ws.send(.data(data)) { _ in }
    }

    /// Update the session configuration.
    public func updateConfig(_ newConfig: VoiceStreamConfig) async throws {
        try await sendConfig(newConfig)
    }

    /// Signal end of audio. Returns the session summary.
    public func end() async throws -> VoiceSessionSummaryEvent {
        guard let ws = webSocket, isActive else {
            throw TuteliqError.validationError("Voice stream is not connected")
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.summaryContinuation = continuation
            lock.unlock()

            let msg = try! JSONSerialization.data(withJSONObject: ["type": "end"])
            ws.send(.string(String(data: msg, encoding: .utf8)!)) { _ in }
        }
    }

    /// Force-close the connection immediately.
    public func close() {
        lock.lock()
        _isActive = false
        lock.unlock()

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Private

    private func sendConfig(_ config: VoiceStreamConfig) async throws {
        guard let ws = webSocket else { return }

        var payload: [String: Any] = ["type": "config"]
        if let interval = config.intervalSeconds {
            payload["interval_seconds"] = interval
        }
        if let types = config.analysisTypes {
            payload["analysis_types"] = types
        }
        if let ctx = config.context {
            var contextDict: [String: String] = [:]
            if let l = ctx.language {
                contextDict["language"] = l
            }
            if let a = ctx.ageGroup {
                contextDict["age_group"] = a
            }
            if let r = ctx.relationship {
                contextDict["relationship"] = r
            }
            if let p = ctx.platform {
                contextDict["platform"] = p
            }
            payload["context"] = contextDict
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        try await ws.send(.string(String(data: data, encoding: .utf8)!))
    }

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case let .success(message):
                self.handleMessage(message)
                self.listenForMessages()

            case .failure:
                self.lock.lock()
                self._isActive = false
                let readyCont = self.readyContinuation
                self.readyContinuation = nil
                let summaryCont = self.summaryContinuation
                self.summaryContinuation = nil
                self.lock.unlock()

                self.handlers.onClose?(.goingAway, "Connection closed")
                readyCont?.resume(throwing: TuteliqError.networkError("Connection closed before ready"))
                summaryCont?.resume(throwing: TuteliqError.networkError("Connection closed before summary"))
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case let .string(str):
            text = str
        case let .data(data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let jsonData = text.data(using: .utf8),
              let data = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = data["type"] as? String else { return }

        switch type {
        case "ready":
            let event = VoiceReadyEvent(data: data)
            lock.lock()
            _sessionId = event.sessionId
            let cont = readyContinuation
            readyContinuation = nil
            lock.unlock()
            handlers.onReady?(event)
            cont?.resume()

        case "transcription":
            handlers.onTranscription?(VoiceTranscriptionEvent(data: data))

        case "alert":
            handlers.onAlert?(VoiceAlertEvent(data: data))

        case "session_summary":
            let event = VoiceSessionSummaryEvent(data: data)
            handlers.onSessionSummary?(event)
            lock.lock()
            let cont = summaryContinuation
            summaryContinuation = nil
            lock.unlock()
            cont?.resume(returning: event)

        case "config_updated":
            handlers.onConfigUpdated?(VoiceConfigUpdatedEvent(data: data))

        case "error":
            handlers.onError?(VoiceErrorEvent(data: data))

        default:
            break
        }
    }
}
