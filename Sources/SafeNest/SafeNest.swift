import Foundation

/// SafeNest - AI-powered child safety analysis
///
/// ```swift
/// let safenest = SafeNest(apiKey: "your-api-key")
///
/// let result = try await safenest.detectBullying(
///     content: "You're not welcome here"
/// )
///
/// if result.isBullying {
///     print("Severity: \(result.severity)")
/// }
/// ```
public final class SafeNest: @unchecked Sendable {

    // MARK: - Properties

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private let maxRetries: Int
    private let retryDelay: TimeInterval

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Current usage statistics (updated after each request)
    public private(set) var usage: Usage?

    /// Request ID from the last request
    public private(set) var lastRequestId: String?

    /// Latency of the last request in seconds
    public private(set) var lastLatency: TimeInterval?

    // MARK: - Initialization

    /// Create a new SafeNest client
    /// - Parameters:
    ///   - apiKey: Your SafeNest API key
    ///   - timeout: Request timeout in seconds (default: 30)
    ///   - maxRetries: Number of retry attempts (default: 3)
    ///   - retryDelay: Initial retry delay in seconds (default: 1)
    public init(
        apiKey: String,
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1
    ) {
        precondition(!apiKey.isEmpty, "API key is required")
        precondition(apiKey.count >= 10, "API key appears to be invalid")

        self.apiKey = apiKey
        self.baseURL = URL(string: "https://api.safenest.dev")!
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - Safety Detection

    /// Detect bullying in content
    public func detectBullying(_ input: DetectBullyingInput) async throws -> BullyingResult {
        var body: [String: Any] = ["text": input.content]
        if let context = input.context {
            body["context"] = encodeContext(context)
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/safety/bullying", body: body)
    }

    /// Convenience method for simple bullying detection
    public func detectBullying(content: String, context: AnalysisContext? = nil) async throws -> BullyingResult {
        try await detectBullying(DetectBullyingInput(content: content, context: context))
    }

    /// Detect grooming patterns in a conversation
    public func detectGrooming(_ input: DetectGroomingInput) async throws -> GroomingResult {
        var body: [String: Any] = [
            "messages": input.messages.map { [
                "sender_role": $0.role.rawValue,
                "text": $0.content
            ] as [String: Any] }
        ]

        var context: [String: Any] = [:]
        if let childAge = input.childAge {
            context["child_age"] = childAge
        }
        if let ctx = input.context {
            context.merge(encodeContext(ctx)) { _, new in new }
        }
        if !context.isEmpty {
            body["context"] = context
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/safety/grooming", body: body)
    }

    /// Detect unsafe content
    public func detectUnsafe(_ input: DetectUnsafeInput) async throws -> UnsafeResult {
        var body: [String: Any] = ["text": input.content]
        if let context = input.context {
            body["context"] = encodeContext(context)
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/safety/unsafe", body: body)
    }

    /// Convenience method for simple unsafe detection
    public func detectUnsafe(content: String, context: AnalysisContext? = nil) async throws -> UnsafeResult {
        try await detectUnsafe(DetectUnsafeInput(content: content, context: context))
    }

    /// Quick analysis - runs bullying and unsafe detection in parallel
    public func analyze(_ input: AnalyzeInput) async throws -> AnalyzeResult {
        let include = input.include ?? [.bullying, .unsafe]

        async let bullyingTask: BullyingResult? = include.contains(.bullying)
            ? try detectBullying(content: input.content, context: input.context)
            : nil

        async let unsafeTask: UnsafeResult? = include.contains(.unsafe)
            ? try detectUnsafe(content: input.content, context: input.context)
            : nil

        let (bullyingResult, unsafeResult) = try await (bullyingTask, unsafeTask)

        // Calculate max risk score
        var maxRiskScore = 0.0
        if let bullying = bullyingResult {
            maxRiskScore = max(maxRiskScore, bullying.riskScore)
        }
        if let unsafe = unsafeResult {
            maxRiskScore = max(maxRiskScore, unsafe.riskScore)
        }

        // Determine risk level
        let riskLevel: RiskLevel
        switch maxRiskScore {
        case 0.9...: riskLevel = .critical
        case 0.7..<0.9: riskLevel = .high
        case 0.5..<0.7: riskLevel = .medium
        case 0.3..<0.5: riskLevel = .low
        default: riskLevel = .safe
        }

        // Build summary
        var findings: [String] = []
        if let bullying = bullyingResult, bullying.isBullying {
            findings.append("Bullying detected (\(bullying.severity.rawValue))")
        }
        if let unsafe = unsafeResult, unsafe.unsafe {
            findings.append("Unsafe content: \(unsafe.categories.joined(separator: ", "))")
        }
        let summary = findings.isEmpty ? "No safety concerns detected." : findings.joined(separator: ". ")

        // Determine recommended action
        var recommendedAction = "none"
        if bullyingResult?.recommendedAction == "immediate_intervention" ||
           unsafeResult?.recommendedAction == "immediate_intervention" {
            recommendedAction = "immediate_intervention"
        } else if bullyingResult?.recommendedAction == "flag_for_moderator" ||
                  unsafeResult?.recommendedAction == "flag_for_moderator" {
            recommendedAction = "flag_for_moderator"
        } else if bullyingResult?.recommendedAction == "monitor" ||
                  unsafeResult?.recommendedAction == "monitor" {
            recommendedAction = "monitor"
        }

        return AnalyzeResult(
            riskLevel: riskLevel,
            riskScore: maxRiskScore,
            summary: summary,
            bullying: bullyingResult,
            unsafe: unsafeResult,
            recommendedAction: recommendedAction,
            externalId: input.externalId,
            metadata: input.metadata?.mapValues { AnyCodable($0) }
        )
    }

    /// Convenience method for simple analysis
    public func analyze(content: String, context: AnalysisContext? = nil) async throws -> AnalyzeResult {
        try await analyze(AnalyzeInput(content: content, context: context))
    }

    // MARK: - Emotion Analysis

    /// Analyze emotions in content or conversation
    public func analyzeEmotions(_ input: AnalyzeEmotionsInput) async throws -> EmotionsResult {
        var body: [String: Any] = [:]

        if let content = input.content {
            body["messages"] = [["sender": "user", "text": content]]
        } else if let messages = input.messages {
            body["messages"] = messages.map { [
                "sender": $0.sender,
                "text": $0.content
            ] }
        }

        if let context = input.context {
            body["context"] = encodeContext(context)
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/analysis/emotions", body: body)
    }

    /// Convenience method for simple emotion analysis
    public func analyzeEmotions(content: String, context: AnalysisContext? = nil) async throws -> EmotionsResult {
        try await analyzeEmotions(AnalyzeEmotionsInput(content: content, context: context))
    }

    // MARK: - Guidance

    /// Get age-appropriate action guidance
    public func getActionPlan(_ input: GetActionPlanInput) async throws -> ActionPlanResult {
        var body: [String: Any] = [
            "role": (input.audience ?? .parent).rawValue,
            "situation": input.situation
        ]

        if let childAge = input.childAge {
            body["child_age"] = childAge
        }
        if let severity = input.severity {
            body["severity"] = severity.rawValue
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/guidance/action-plan", body: body)
    }

    // MARK: - Reports

    /// Generate an incident report
    public func generateReport(_ input: GenerateReportInput) async throws -> ReportResult {
        var body: [String: Any] = [
            "messages": input.messages.map { [
                "sender": $0.sender,
                "text": $0.content
            ] }
        ]

        var meta: [String: Any] = [:]
        if let childAge = input.childAge {
            meta["child_age"] = childAge
        }
        if let incidentType = input.incidentType {
            meta["type"] = incidentType
        }
        if !meta.isEmpty {
            body["meta"] = meta
        }
        if let externalId = input.externalId {
            body["external_id"] = externalId
        }
        if let metadata = input.metadata {
            body["metadata"] = metadata
        }

        return try await request(method: "POST", path: "/api/v1/reports/incident", body: body)
    }

    // MARK: - Private Helpers

    private func encodeContext(_ context: AnalysisContext) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let language = context.language { dict["language"] = language }
        if let ageGroup = context.ageGroup { dict["age_group"] = ageGroup }
        if let relationship = context.relationship { dict["relationship"] = relationship }
        if let platform = context.platform { dict["platform"] = platform }
        return dict
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await performRequest(method: method, path: path, body: body)
            } catch let error as SafeNestError {
                // Don't retry auth or validation errors
                switch error {
                case .authenticationError, .validationError, .notFoundError:
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = error
            }

            // Exponential backoff
            if attempt < maxRetries - 1 {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? SafeNestError.unknownError("Request failed after \(maxRetries) attempts")
    }

    private func performRequest<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]?
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let startTime = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw SafeNestError.timeoutError("Request timed out after \(timeout) seconds")
            case .notConnectedToInternet, .networkConnectionLost:
                throw SafeNestError.networkError("No internet connection")
            default:
                throw SafeNestError.networkError(error.localizedDescription)
            }
        }

        lastLatency = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SafeNestError.unknownError("Invalid response")
        }

        // Extract metadata from headers
        lastRequestId = httpResponse.value(forHTTPHeaderField: "X-Request-ID")

        if let limit = httpResponse.value(forHTTPHeaderField: "X-Usage-Limit").flatMap(Int.init),
           let used = httpResponse.value(forHTTPHeaderField: "X-Usage-Used").flatMap(Int.init),
           let remaining = httpResponse.value(forHTTPHeaderField: "X-Usage-Remaining").flatMap(Int.init) {
            usage = Usage(limit: limit, used: used, remaining: remaining)
        }

        // Handle errors
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "Request failed"

            switch httpResponse.statusCode {
            case 400:
                throw SafeNestError.validationError(message, details: errorResponse?.error.details?.value)
            case 401:
                throw SafeNestError.authenticationError(message)
            case 404:
                throw SafeNestError.notFoundError(message)
            case 429:
                throw SafeNestError.rateLimitError(message)
            case 500...:
                throw SafeNestError.serverError(message, statusCode: httpResponse.statusCode)
            default:
                throw SafeNestError.unknownError(message)
            }
        }

        return try decoder.decode(T.self, from: data)
    }
}
