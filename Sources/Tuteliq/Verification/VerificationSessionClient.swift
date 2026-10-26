import Foundation

/// Talks to the session-scoped verification endpoints, exactly like the hosted
/// web flow: every decision (document checks, liveness, face match, age) is
/// made server-side. This client only uploads what the device captured.
public final class VerificationSessionClient: Sendable {
    public let credentials: VerificationSessionCredentials
    private let session: URLSession
    private let timeout: TimeInterval

    public init(credentials: VerificationSessionCredentials, session: URLSession? = nil, timeout: TimeInterval = 60) {
        self.credentials = credentials
        self.timeout = timeout
        if let session {
            self.session = session
        } else {
            // Ephemeral: a biometric flow keeps no cookies, cache or credentials on disk.
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            self.session = URLSession(configuration: config)
        }
    }

    /// The session ID as one path segment, percent-encoded once. A link's ID is
    /// already restricted to letters, digits, `-` and `_`; credentials built by
    /// hand may hold anything, and still cannot leave the segment.
    private var sessionPath: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let id = credentials.sessionId == "." || credentials.sessionId == ".."
            ? credentials.sessionId.replacingOccurrences(of: ".", with: "%2E")
            : credentials.sessionId.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "/api/v1/verify/session/\(id)"
    }

    // MARK: - Endpoints

    /// `GET /session/:id/mode`: the verification mode and UI language for this end user.
    public func fetchMode() async throws -> SessionModeInfo {
        try await send(request(path: sessionPath + "/mode", method: "GET"))
    }

    /// `POST /session/:id/progress`. Best effort: failures are ignored, as on the web.
    public func reportProgress(_ step: VerificationProgressStep) async {
        var request = request(path: sessionPath + "/progress", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["step": step.rawValue])
        _ = try? await session.data(for: request)
    }

    /// `GET /verify/age/challenge`: a server-signed liveness challenge, valid ~5 minutes, single use.
    public func fetchLivenessChallenge() async throws -> LivenessChallenge {
        try await send(request(path: "/api/v1/verify/age/challenge", method: "GET"))
    }

    /// Fetches a liveness challenge and returns a builder for its token, on the
    /// server's clock: the offset is read from the response's `Date` header, so a
    /// device clock a few seconds out does not fail the user. Start the first
    /// prompt after this returns.
    public func startLiveness() async throws -> LivenessTokenBuilder {
        let sent = Date()
        let (challenge, response): (LivenessChallenge, HTTPURLResponse) = try await sendWithResponse(
            request(path: "/api/v1/verify/age/challenge", method: "GET")
        )
        let received = Date()
        var offset: TimeInterval = 0
        if let header = response.value(forHTTPHeaderField: "Date"), let server = Self.httpDate(header) {
            // The header has whole seconds; compare with the middle of the round trip.
            offset = server.timeIntervalSince(sent.addingTimeInterval(received.timeIntervalSince(sent) / 2))
            // Within a second is clock rounding, not drift.
            if abs(offset) < 1 {
                offset = 0
            }
        }
        return LivenessTokenBuilder(challenge: challenge, createdAt: received, clockOffset: offset)
    }

    static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    /// `POST /session/:id/validate-document`: quality check, then server-side OCR and face template.
    /// When `retained` is true, submit needn't carry this image.
    public func validateDocument(
        _ jpeg: Data,
        side: DocumentSide,
        documentType: DocumentType,
        captureSource: DocumentCaptureSource,
        context: CaptureContext? = nil
    ) async throws -> DocumentValidationResult {
        var form = MultipartForm()
        // Fields first: the server reads `side` before the file.
        form.addField("side", side.rawValue)
        form.addField("document_type", documentType.rawValue)
        form.addField("document_capture_source", captureSource.rawValue)
        form.addContext(context)
        form.addFile("document", filename: "document.jpg", mimeType: "image/jpeg", data: jpeg)
        return try await send(multipart(path: sessionPath + "/validate-document", form: form))
    }

    /// `POST /session/:id/validate-chip`: uploads the raw, signed chip files for
    /// server-side passive authentication and data extraction.
    ///
    /// Returns `nil` when the API doesn't offer chip validation (its route-not-found
    /// answer, `NF_5002`), so callers can continue with the photographed document
    /// alone. Any other 404, such as a missing session, a wrong base URL or a proxy,
    /// is thrown, so chip evidence is never dropped silently.
    public func validateChip(_ files: [ChipFile: Data], documentType: DocumentType, context: CaptureContext? = nil) async throws -> ChipValidationResult? {
        var form = MultipartForm()
        form.addField("document_type", documentType.rawValue)
        form.addContext(context)
        for file in ChipFile.allCases {
            guard let data = files[file] else { continue }
            form.addFile(file.rawValue, filename: "\(file.rawValue).bin", mimeType: "application/octet-stream", data: data)
        }
        do {
            return try await send(multipart(path: sessionPath + "/validate-chip", form: form))
        } catch let VerificationError.server(code, _, status) where status == 404 && code == "NF_5002" {
            return nil
        }
    }

    /// `POST /session/:id/validate-selfie`. With a liveness capture, the server
    /// runs liveness, age and the face match now (`assessed: true`).
    public func validateSelfie(_ jpeg: Data, liveness: LivenessCapture?, context: CaptureContext? = nil) async throws -> SelfieValidationResult {
        var form = MultipartForm()
        if let liveness {
            form.addField("liveness_token", liveness.token)
        }
        form.addFrameKinds(liveness)
        form.addContext(context)
        form.addFile("selfie", filename: "selfie.jpg", mimeType: "image/jpeg", data: jpeg)
        for frame in liveness?.frames ?? [] {
            form.addFile("liveness_frame", filename: "liveness_frame.jpg", mimeType: "image/jpeg", data: frame)
        }
        return try await send(multipart(path: sessionPath + "/validate-selfie", form: form))
    }

    /// `POST /session/:id/submit`.
    public func submit(_ submission: SessionSubmission) async throws -> SessionSubmitResult {
        var form = MultipartForm()
        if let type = submission.documentType {
            form.addField("document_type", type.rawValue)
        }
        if let token = submission.liveness?.token {
            form.addField("liveness_token", token)
        }
        form.addFrameKinds(submission.liveness)
        if let source = submission.documentCaptureSource {
            form.addField("document_capture_source", source.rawValue)
        }
        form.addContext(submission.context)
        if let front = submission.documentFront {
            form.addFile("id_front", filename: "id_front.jpg", mimeType: "image/jpeg", data: front)
            if submission.documentType == .passport {
                form.addFile("passport", filename: "passport.jpg", mimeType: "image/jpeg", data: front)
            }
        }
        if let back = submission.documentBack {
            form.addFile("id_back", filename: "id_back.jpg", mimeType: "image/jpeg", data: back)
        }
        for (index, frame) in submission.tiltFrames.prefix(2).enumerated() {
            form.addFile("tilt_frame_\(index + 1)", filename: "tilt_\(index + 1).jpg", mimeType: "image/jpeg", data: frame)
        }
        if let selfie = submission.selfie {
            form.addFile("selfie", filename: "selfie.jpg", mimeType: "image/jpeg", data: selfie)
        }
        for frame in submission.liveness?.frames ?? [] {
            form.addFile("liveness_frame", filename: "liveness_frame.jpg", mimeType: "image/jpeg", data: frame)
        }
        return try await send(multipart(path: sessionPath + "/submit", form: form))
    }

    // MARK: - Transport

    private func request(path: String, method: String) -> URLRequest {
        // Built from the already-encoded path in one step: appendingPathComponent would encode it again.
        var components = URLComponents(url: credentials.apiBaseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = components.percentEncodedPath.trimmingSuffix("/") + path
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipart(path: String, form: MultipartForm) -> URLRequest {
        var request = request(path: path, method: "POST")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        try await sendWithResponse(request).0
    }

    private func sendWithResponse<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw VerificationError.timeout
            }
            if error.code == .cancelled {
                throw VerificationError.cancelled
            }
            throw VerificationError.network(error.localizedDescription)
        } catch is CancellationError {
            throw VerificationError.cancelled
        }

        guard let http = response as? HTTPURLResponse else { throw VerificationError.invalidResponse("Not HTTP") }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, body: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        do {
            return try (JSONDecoder().decode(T.self, from: data), http)
        } catch {
            throw VerificationError.invalidResponse(String(describing: error))
        }
    }

    static func error(status: Int, body: Data, retryAfter: String?, now: Date = Date()) -> VerificationError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let code: String?
                let message: String?
            }

            let error: Body?
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
        let code = envelope?.error?.code
        let message = envelope?.error?.message ?? HTTPURLResponse.localizedString(forStatusCode: status)

        switch code {
        case "VERIFY_11006": return .sessionNotFound
        case "VERIFY_11007": return .sessionExpired
        case "VERIFY_11008": return .invalidSessionToken
        case "VERIFY_11009": return .sessionAlreadyCompleted
        case "VERIFY_11010": return .sessionWrongState
        default: break
        }
        if status == 410 {
            return .sessionExpired
        }
        if status == 429 {
            return .rateLimited(retryAfter: retryAfter.flatMap { retryDelay($0, now: now) })
        }
        return .server(code: code, message: message, statusCode: status)
    }

    /// `Retry-After` is whole seconds or an HTTP date (RFC 9110 §10.2.3). Anything
    /// else is ignored, and the delay is capped at a day.
    static func retryDelay(_ header: String, now: Date) -> TimeInterval? {
        let maxDelay: TimeInterval = 86400
        if !header.isEmpty, header.utf8.allSatisfy({ (0x30 ... 0x39).contains($0) }) {
            return min(TimeInterval(header) ?? maxDelay, maxDelay)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: header) else { return nil }
        return min(max(date.timeIntervalSince(now), 0), maxDelay)
    }
}

/// The credentials hold the session token: nothing that prints or dumps the client shows it.
extension VerificationSessionClient: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "VerificationSessionClient(\(credentials))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["credentials": credentials], displayStyle: .class)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

/// What to send with `submit`. Leave out anything the server already holds
/// (a document side `retained` by validate-document, or a selfie `assessed` by validate-selfie).
public struct SessionSubmission: Sendable {
    public var documentType: DocumentType?
    public var documentFront: Data?
    public var documentBack: Data?
    public var documentCaptureSource: DocumentCaptureSource?
    /// Two frames of the document tilted, for the server's document check (camera captures only).
    public var tiltFrames: [Data]
    public var selfie: Data?
    public var liveness: LivenessCapture?
    /// What captured this submission. See ``CaptureContext``.
    public var context: CaptureContext?

    public init(
        documentType: DocumentType? = nil,
        documentFront: Data? = nil,
        documentBack: Data? = nil,
        documentCaptureSource: DocumentCaptureSource? = nil,
        tiltFrames: [Data] = [],
        selfie: Data? = nil,
        liveness: LivenessCapture? = nil,
        context: CaptureContext? = nil
    ) {
        self.documentType = documentType
        self.documentFront = documentFront
        self.documentBack = documentBack
        self.documentCaptureSource = documentCaptureSource
        self.tiltFrames = tiltFrames
        self.selfie = selfie
        self.liveness = liveness
        self.context = context
    }
}

/// `multipart/form-data` body builder.
struct MultipartForm {
    let boundary = "TuteliqBoundary-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// `liveness_frame_kinds`: what each `liveness_frame` shows, in upload order (JSON array).
    mutating func addFrameKinds(_ liveness: LivenessCapture?) {
        guard let kinds = liveness?.frameKinds, !kinds.isEmpty,
              let data = try? JSONEncoder().encode(kinds.map(\.rawValue)) else { return }
        addField("liveness_frame_kinds", String(decoding: data, as: UTF8.self))
    }

    /// The `capture_context` field, when there is one.
    mutating func addContext(_ context: CaptureContext?) {
        if let json = context?.encodedJSON() {
            addField("capture_context", json)
        }
    }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func encoded() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }
}
