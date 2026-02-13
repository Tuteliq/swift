import Foundation

/// Tuteliq — AI-powered child safety analysis SDK.
///
/// The primary interface for the Tuteliq API. Provides methods for detecting
/// bullying, grooming, and unsafe content, as well as emotion analysis,
/// guidance, reports, and platform management.
///
/// ```swift
/// let tuteliq = try Tuteliq(apiKey: "your-api-key")
///
/// let result = try await tuteliq.detectBullying(content: "message text")
/// if result.isBullying {
///     print("Severity: \(result.severity)")
/// }
/// ```
///
/// All API methods are `async` and the client is thread-safe. It can be shared
/// across tasks and actors. Metadata properties (`usage`, `lastRequestId`,
/// `lastLatency`, `rateLimitInfo`) reflect the most recently completed request.
public final class Tuteliq: @unchecked Sendable {

    // MARK: - Properties

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let cacheTTL: TimeInterval

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Thread-safe mutable state
    private let stateLock = NSLock()
    private var _usage: Usage?
    private var _lastRequestId: String?
    private var _lastLatency: TimeInterval?
    private var _rateLimitInfo: RateLimitInfo?
    private var _cache: [String: CacheEntry] = [:]

    private struct CacheEntry {
        let data: Data
        let expiry: Date
    }

    /// Monthly usage statistics, updated after each request.
    public var usage: Usage? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _usage
    }

    /// Request ID from the most recent API call.
    public var lastRequestId: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastRequestId
    }

    /// Latency of the most recent API call in seconds.
    public var lastLatency: TimeInterval? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastLatency
    }

    /// Rate limit information from the most recent API call.
    public var rateLimitInfo: RateLimitInfo? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _rateLimitInfo
    }

    // MARK: - Initialization

    /// Creates a new Tuteliq client.
    ///
    /// - Parameters:
    ///   - apiKey: Your Tuteliq API key (minimum 10 characters).
    ///   - baseURL: Custom API base URL (defaults to `https://api.tuteliq.ai`).
    ///   - timeout: Request timeout in seconds (default: 30).
    ///   - maxRetries: Number of retry attempts for transient failures (default: 3).
    ///   - retryDelay: Initial retry delay in seconds, doubled each attempt (default: 1).
    ///   - cacheTTL: Time-to-live for GET response cache in seconds (default: 0 = disabled).
    ///   - session: Custom `URLSession` for advanced configuration or testing.
    /// - Throws: ``TuteliqError/validationError(_:details:)`` if the API key is empty or too short.
    public init(
        apiKey: String,
        baseURL: String = "https://api.tuteliq.ai",
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1,
        cacheTTL: TimeInterval = 0,
        session: URLSession? = nil
    ) throws {
        guard !apiKey.isEmpty else {
            throw TuteliqError.validationError("API key is required")
        }
        guard apiKey.count >= 10 else {
            throw TuteliqError.validationError("API key appears to be invalid (too short)")
        }
        guard let url = URL(string: baseURL) else {
            throw TuteliqError.validationError("Invalid base URL: \(baseURL)")
        }

        self.apiKey = apiKey
        self.baseURL = url
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.cacheTTL = cacheTTL

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Safety Detection

    /// Detect bullying in text content.
    ///
    /// - Parameter input: The bullying detection input.
    /// - Returns: Analysis result with severity, risk score, and recommended action.
    /// - Throws: ``TuteliqError`` on failure.
    public func detectBullying(_ input: DetectBullyingInput) async throws -> BullyingResult {
        let body = BullyingRequest(
            text: input.content,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/safety/bullying", body: body)
    }

    /// Convenience method for simple bullying detection.
    ///
    /// - Parameters:
    ///   - content: Text to analyze.
    ///   - context: Optional analysis context.
    /// - Returns: Analysis result.
    public func detectBullying(content: String, context: AnalysisContext? = nil) async throws -> BullyingResult {
        try await detectBullying(DetectBullyingInput(content: content, context: context))
    }

    /// Detect grooming patterns in a conversation.
    ///
    /// - Parameter input: The grooming detection input with conversation messages.
    /// - Returns: Analysis result with grooming risk level and identified flags.
    /// - Throws: ``TuteliqError`` on failure.
    public func detectGrooming(_ input: DetectGroomingInput) async throws -> GroomingResult {
        var ctx = contextPayload(input.context)
        if let childAge = input.childAge { ctx.childAge = childAge }
        let body = GroomingRequest(
            messages: input.messages.map { GroomingMessagePayload(senderRole: $0.role.rawValue, text: $0.content) },
            context: ctx,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/safety/grooming", body: body)
    }

    /// Detect unsafe content (self-harm, violence, hate speech, etc.).
    ///
    /// - Parameter input: The unsafe content detection input.
    /// - Returns: Analysis result with categories, severity, and risk score.
    /// - Throws: ``TuteliqError`` on failure.
    public func detectUnsafe(_ input: DetectUnsafeInput) async throws -> UnsafeResult {
        let body = UnsafeRequest(
            text: input.content,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/safety/unsafe", body: body)
    }

    /// Convenience method for simple unsafe content detection.
    public func detectUnsafe(content: String, context: AnalysisContext? = nil) async throws -> UnsafeResult {
        try await detectUnsafe(DetectUnsafeInput(content: content, context: context))
    }

    // MARK: - Quick Analysis

    /// Run bullying and unsafe detection in parallel.
    ///
    /// This is a client-side convenience that calls both endpoints concurrently
    /// and merges the results. For server-side batching, use ``batchAnalyze(_:)``.
    ///
    /// - Parameter input: Combined analysis input.
    /// - Returns: Merged result with overall risk level and individual results.
    /// - Throws: ``TuteliqError`` on failure.
    public func analyze(_ input: AnalyzeInput) async throws -> AnalyzeResult {
        let include = input.include ?? [.bullying, .unsafe]
        let metadataRaw = input.metadata?.mapValues { $0.value }

        let bullyingInput = DetectBullyingInput(
            content: input.content, context: input.context,
            externalId: input.externalId, customerId: input.customerId,
            metadata: metadataRaw
        )
        let unsafeInput = DetectUnsafeInput(
            content: input.content, context: input.context,
            externalId: input.externalId, customerId: input.customerId,
            metadata: metadataRaw
        )

        async let bullyingTask: BullyingResult? = include.contains(.bullying)
            ? try detectBullying(bullyingInput) : nil
        async let unsafeTask: UnsafeResult? = include.contains(.unsafe)
            ? try detectUnsafe(unsafeInput) : nil

        let (bullyingResult, unsafeResult) = try await (bullyingTask, unsafeTask)

        var maxRiskScore = 0.0
        if let b = bullyingResult { maxRiskScore = max(maxRiskScore, b.riskScore) }
        if let u = unsafeResult { maxRiskScore = max(maxRiskScore, u.riskScore) }

        let riskLevel: RiskLevel
        switch maxRiskScore {
        case 0.9...: riskLevel = .critical
        case 0.7..<0.9: riskLevel = .high
        case 0.5..<0.7: riskLevel = .medium
        case 0.3..<0.5: riskLevel = .low
        default: riskLevel = .safe
        }

        var findings: [String] = []
        if let b = bullyingResult, b.isBullying {
            findings.append("Bullying detected (\(b.severity.rawValue))")
        }
        if let u = unsafeResult, u.unsafe {
            findings.append("Unsafe content: \(u.categories.joined(separator: ", "))")
        }
        let summary = findings.isEmpty ? "No safety concerns detected." : findings.joined(separator: ". ")

        let actions = [bullyingResult?.recommendedAction, unsafeResult?.recommendedAction].compactMap { $0 }
        let recommendedAction: String
        if actions.contains(RecommendedAction.immediateIntervention.rawValue) {
            recommendedAction = RecommendedAction.immediateIntervention.rawValue
        } else if actions.contains(RecommendedAction.flagForModerator.rawValue) {
            recommendedAction = RecommendedAction.flagForModerator.rawValue
        } else if actions.contains(RecommendedAction.monitor.rawValue) {
            recommendedAction = RecommendedAction.monitor.rawValue
        } else {
            recommendedAction = RecommendedAction.none.rawValue
        }

        return AnalyzeResult(
            riskLevel: riskLevel, riskScore: maxRiskScore, summary: summary,
            bullying: bullyingResult, unsafe: unsafeResult,
            recommendedAction: recommendedAction,
            externalId: input.externalId, customerId: input.customerId,
            metadata: input.metadata
        )
    }

    /// Convenience method for simple combined analysis.
    public func analyze(content: String, context: AnalysisContext? = nil) async throws -> AnalyzeResult {
        try await analyze(AnalyzeInput(content: content, context: context))
    }

    // MARK: - Emotion Analysis

    /// Analyze emotions in content or conversation.
    ///
    /// - Parameter input: Emotion analysis input (single text or message array).
    /// - Returns: Dominant emotions, scores, trend, and followup recommendation.
    /// - Throws: ``TuteliqError`` on failure.
    public func analyzeEmotions(_ input: AnalyzeEmotionsInput) async throws -> EmotionsResult {
        let messages: [EmotionMessagePayload]
        if let content = input.content {
            messages = [EmotionMessagePayload(sender: "user", text: content)]
        } else if let msgs = input.messages {
            messages = msgs.map { EmotionMessagePayload(sender: $0.sender, text: $0.content) }
        } else {
            messages = []
        }
        let body = EmotionsRequest(
            messages: messages,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/analysis/emotions", body: body)
    }

    /// Convenience method for simple emotion analysis.
    public func analyzeEmotions(content: String, context: AnalysisContext? = nil) async throws -> EmotionsResult {
        try await analyzeEmotions(AnalyzeEmotionsInput(content: content, context: context))
    }

    // MARK: - Guidance

    /// Generate an age-appropriate action plan.
    ///
    /// - Parameter input: Action plan input with situation and target audience.
    /// - Returns: Steps, tone, and reading level for the target audience.
    /// - Throws: ``TuteliqError`` on failure.
    public func getActionPlan(_ input: GetActionPlanInput) async throws -> ActionPlanResult {
        let body = ActionPlanRequest(
            role: (input.audience ?? .parent).rawValue,
            situation: input.situation,
            childAge: input.childAge,
            severity: input.severity?.rawValue,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/guidance/action-plan", body: body)
    }

    // MARK: - Reports

    /// Generate a professional incident report.
    ///
    /// - Parameter input: Report input with conversation messages and metadata.
    /// - Returns: Summary, risk level, categories, and next steps.
    /// - Throws: ``TuteliqError`` on failure.
    public func generateReport(_ input: GenerateReportInput) async throws -> ReportResult {
        let hasMeta = input.childAge != nil || input.incidentType != nil
            || input.conversationId != nil || input.timestampRange != nil
        let body = ReportRequest(
            messages: input.messages.map { ReportMessagePayload(sender: $0.sender, text: $0.content) },
            meta: hasMeta ? ReportMeta(
                childAge: input.childAge,
                type: input.incidentType,
                conversationId: input.conversationId,
                timestampRange: input.timestampRange
            ) : nil,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata
        )
        return try await request(method: "POST", path: "/api/v1/reports/incident", body: body)
    }

    // MARK: - Policy

    /// Get current policy configuration.
    ///
    /// - Returns: The active policy configuration.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func getPolicy() async throws -> PolicyResult {
        try await request(method: "GET", path: "/api/v1/policy")
    }

    /// Update the policy configuration.
    ///
    /// - Parameter config: New policy configuration dictionary.
    /// - Returns: Updated policy configuration.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func updatePolicy(_ config: [String: AnyCodable]) async throws -> PolicyResult {
        let body = PolicyUpdateRequest(config: config)
        return try await request(method: "PUT", path: "/api/v1/policy", body: body)
    }

    // MARK: - Batch Analysis

    /// Analyze multiple items in a single request (max 50).
    ///
    /// Use ``BatchResultItem/decodeResult(as:)`` to decode typed results:
    /// ```swift
    /// let batch = try await tuteliq.batchAnalyze(input)
    /// for item in batch.results where item.success {
    ///     if item.type == "bullying" {
    ///         let result = try item.decodeResult(as: BullyingResult.self)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter input: Batch analysis input with typed items.
    /// - Returns: Individual results and a processing summary.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func batchAnalyze(_ input: BatchAnalyzeInput) async throws -> BatchAnalyzeResult {
        let body = BatchRequest(
            items: input.items.map(encodeBatchItem),
            parallel: input.parallel
        )
        return try await request(method: "POST", path: "/api/v1/batch/analyze", body: body)
    }

    // MARK: - Usage

    /// Get usage summary for a specific date.
    ///
    /// - Parameter date: Date in `YYYY-MM-DD` format (defaults to today).
    /// - Returns: Request counts and quota information.
    public func getUsageSummary(date: String? = nil) async throws -> UsageSummaryResult {
        var query: [URLQueryItem]?
        if let date = date { query = [URLQueryItem(name: "date", value: date)] }
        return try await request(method: "GET", path: "/api/v1/usage/summary", query: query)
    }

    /// Get usage history for the past N days.
    ///
    /// - Parameter days: Number of days (1-30, defaults to 7).
    /// - Returns: Daily request counts.
    public func getUsageHistory(days: Int? = nil) async throws -> UsageHistoryResult {
        var query: [URLQueryItem]?
        if let days = days { query = [URLQueryItem(name: "days", value: "\(days)")] }
        return try await request(method: "GET", path: "/api/v1/usage/history", query: query)
    }

    /// Get current rate limit and quota status.
    ///
    /// - Returns: Limits, current usage, and remaining capacity.
    public func getUsageQuota() async throws -> UsageQuotaResult {
        try await request(method: "GET", path: "/api/v1/usage/quota")
    }

    /// Get usage broken down by tool/endpoint.
    ///
    /// - Parameter date: Date in `YYYY-MM-DD` format (defaults to today).
    /// - Returns: Per-tool and per-endpoint request counts.
    public func getUsageByTool(date: String? = nil) async throws -> UsageByToolResult {
        var query: [URLQueryItem]?
        if let date = date { query = [URLQueryItem(name: "date", value: date)] }
        return try await request(method: "GET", path: "/api/v1/usage/by-tool", query: query)
    }

    /// Get monthly usage, limits, and upgrade recommendations.
    ///
    /// - Returns: Billing info, usage stats, and upgrade suggestions.
    public func getUsageMonthly() async throws -> UsageMonthlyResult {
        try await request(method: "GET", path: "/api/v1/usage/monthly")
    }

    // MARK: - Webhooks

    /// List all webhooks for your account.
    ///
    /// - Returns: Array of webhook configurations.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func listWebhooks() async throws -> WebhookListResult {
        try await request(method: "GET", path: "/api/v1/webhooks")
    }

    /// Create a new webhook.
    ///
    /// - Important: The returned ``CreateWebhookResult/secret`` is only shown once.
    ///   Store it securely for signature verification.
    ///
    /// - Parameter input: Webhook creation input.
    /// - Returns: Created webhook with signing secret.
    public func createWebhook(_ input: CreateWebhookInput) async throws -> CreateWebhookResult {
        let body = CreateWebhookRequest(
            name: input.name,
            url: input.url,
            events: input.events.map(\.rawValue),
            headers: input.headers
        )
        return try await request(method: "POST", path: "/api/v1/webhooks", body: body)
    }

    /// Update an existing webhook.
    ///
    /// - Parameters:
    ///   - id: Webhook ID.
    ///   - input: Fields to update (only non-nil fields are sent).
    /// - Returns: Updated webhook configuration.
    public func updateWebhook(id: String, _ input: UpdateWebhookInput) async throws -> UpdateWebhookResult {
        let body = UpdateWebhookRequest(
            name: input.name,
            url: input.url,
            events: input.events?.map(\.rawValue),
            isActive: input.isActive,
            headers: input.headers
        )
        return try await request(method: "PUT", path: "/api/v1/webhooks/\(id)", body: body)
    }

    /// Delete a webhook.
    ///
    /// - Parameter id: Webhook ID.
    /// - Returns: Confirmation of deletion.
    public func deleteWebhook(id: String) async throws -> DeleteResult {
        try await request(method: "DELETE", path: "/api/v1/webhooks/\(id)")
    }

    /// Send a test payload to a webhook.
    ///
    /// - Parameter id: Webhook ID to test.
    /// - Returns: Test result with status code and latency.
    public func testWebhook(id: String) async throws -> TestWebhookResult {
        let body = TestWebhookRequest(webhookId: id)
        return try await request(method: "POST", path: "/api/v1/webhooks/test", body: body)
    }

    /// Regenerate a webhook's signing secret.
    ///
    /// - Important: The old secret is immediately invalidated.
    ///
    /// - Parameter id: Webhook ID.
    /// - Returns: The new signing secret.
    public func regenerateWebhookSecret(id: String) async throws -> RegenerateSecretResult {
        try await request(method: "POST", path: "/api/v1/webhooks/\(id)/regenerate-secret")
    }

    // MARK: - Media Analysis

    /// Analyze audio content for safety concerns.
    ///
    /// Transcribes audio via Whisper and runs the specified safety analyses
    /// on the transcript. Supported formats: mp3, wav, m4a, ogg, flac, webm, mp4.
    ///
    /// ```swift
    /// let audioData = try Data(contentsOf: audioURL)
    /// let input = AnalyzeVoiceInput(file: audioData, filename: "recording.mp3")
    /// let result = try await tuteliq.analyzeVoice(input)
    /// print(result.transcription.text)
    /// print("Risk: \(result.overallRiskScore)")
    /// ```
    ///
    /// - Parameter input: Voice analysis input with audio file data.
    /// - Returns: Transcription with safety analysis results.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func analyzeVoice(_ input: AnalyzeVoiceInput) async throws -> VoiceAnalysisResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        let mimeType = Self.mimeType(for: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.analysisType { body.appendMultipartField(boundary: boundary, name: "analysis_type", value: v.rawValue) }
        if let v = input.fileId { body.appendMultipartField(boundary: boundary, name: "file_id", value: v) }
        if let v = input.externalId { body.appendMultipartField(boundary: boundary, name: "external_id", value: v) }
        if let v = input.customerId { body.appendMultipartField(boundary: boundary, name: "customer_id", value: v) }
        if let v = input.ageGroup { body.appendMultipartField(boundary: boundary, name: "age_group", value: v) }
        if let v = input.language { body.appendMultipartField(boundary: boundary, name: "language", value: v) }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let v = input.childAge { body.appendMultipartField(boundary: boundary, name: "child_age", value: "\(v)") }
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/safety/voice", body: body, boundary: boundary)
    }

    /// Analyze image content for safety concerns.
    ///
    /// Uses vision AI for visual classification and OCR text extraction,
    /// then runs safety analyses on any extracted text. Supported formats: png, jpg, jpeg, gif, webp.
    ///
    /// ```swift
    /// let imageData = try Data(contentsOf: imageURL)
    /// let input = AnalyzeImageInput(file: imageData, filename: "screenshot.png")
    /// let result = try await tuteliq.analyzeImage(input)
    /// print(result.vision.extractedText)
    /// print("Risk: \(result.overallRiskScore)")
    /// ```
    ///
    /// - Parameter input: Image analysis input with image file data.
    /// - Returns: Vision analysis with optional text safety results.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func analyzeImage(_ input: AnalyzeImageInput) async throws -> ImageAnalysisResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        let mimeType = Self.mimeType(for: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.analysisType { body.appendMultipartField(boundary: boundary, name: "analysis_type", value: v.rawValue) }
        if let v = input.fileId { body.appendMultipartField(boundary: boundary, name: "file_id", value: v) }
        if let v = input.externalId { body.appendMultipartField(boundary: boundary, name: "external_id", value: v) }
        if let v = input.customerId { body.appendMultipartField(boundary: boundary, name: "customer_id", value: v) }
        if let v = input.ageGroup { body.appendMultipartField(boundary: boundary, name: "age_group", value: v) }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/safety/image", body: body, boundary: boundary)
    }

    // MARK: - Pricing

    /// Get public pricing plans (no authentication required).
    ///
    /// - Returns: List of pricing plans with features.
    public func getPricing() async throws -> PricingResult {
        try await request(method: "GET", path: "/api/v1/pricing")
    }

    /// Get detailed pricing plans (requires authentication).
    ///
    /// - Returns: Detailed plans including monthly/yearly prices and rate limits.
    public func getPricingDetails() async throws -> PricingDetailsResult {
        try await request(method: "GET", path: "/api/v1/pricing/details")
    }

    // MARK: - Account Management (GDPR)

    /// Delete all account data (GDPR Article 17 — Right to Erasure).
    ///
    /// - Returns: Confirmation with the number of deleted records.
    public func deleteAccountData() async throws -> AccountDeletionResult {
        try await request(method: "DELETE", path: "/api/v1/account/data")
    }

    /// Export all account data as JSON (GDPR Article 20 — Right to Data Portability).
    ///
    /// - Returns: Full data export grouped by collection.
    public func exportAccountData() async throws -> AccountExportResult {
        try await request(method: "GET", path: "/api/v1/account/export")
    }

    /// Record user consent (GDPR Article 7).
    ///
    /// - Parameter input: Consent type and policy version.
    /// - Returns: The created consent record.
    public func recordConsent(_ input: RecordConsentInput) async throws -> ConsentActionResult {
        try await request(method: "POST", path: "/api/v1/account/consent", body: [
            "consent_type": input.consentType.rawValue,
            "version": input.version,
        ])
    }

    /// Get current consent status (GDPR Article 7).
    ///
    /// - Parameter type: Optional filter by consent type.
    /// - Returns: List of consent records.
    public func getConsentStatus(type: ConsentType? = nil) async throws -> ConsentStatusResult {
        var path = "/api/v1/account/consent"
        if let type = type {
            path += "?type=\(type.rawValue)"
        }
        return try await request(method: "GET", path: path)
    }

    /// Withdraw consent (GDPR Article 7.3).
    ///
    /// - Parameter type: Type of consent to withdraw.
    /// - Returns: The withdrawal record.
    public func withdrawConsent(type: ConsentType) async throws -> ConsentActionResult {
        try await request(method: "DELETE", path: "/api/v1/account/consent/\(type.rawValue)")
    }

    /// Rectify user data (GDPR Article 16 — Right to Rectification).
    ///
    /// - Parameter input: Collection, document ID, and fields to update.
    /// - Returns: Confirmation with list of updated fields.
    public func rectifyData(_ input: RectifyDataInput) async throws -> RectifyDataResult {
        try await request(method: "PATCH", path: "/api/v1/account/data", body: [
            "collection": AnyCodable(input.collection),
            "document_id": AnyCodable(input.documentId),
            "fields": AnyCodable(input.fields.mapValues { $0.value }),
        ])
    }

    /// Get audit logs (GDPR Article 15 — Right of Access).
    ///
    /// - Parameters:
    ///   - action: Optional filter by action type.
    ///   - limit: Maximum number of results.
    /// - Returns: List of audit log entries.
    public func getAuditLogs(action: AuditAction? = nil, limit: Int? = nil) async throws -> AuditLogsResult {
        var components: [String] = []
        if let action = action { components.append("action=\(action.rawValue)") }
        if let limit = limit { components.append("limit=\(limit)") }
        let query = components.isEmpty ? "" : "?\(components.joined(separator: "&"))"
        return try await request(method: "GET", path: "/api/v1/account/audit-logs\(query)")
    }

    // MARK: - Breach Management (GDPR Article 33/34)

    /// Log a new data breach.
    ///
    /// - Parameter input: Breach details.
    /// - Returns: The created breach record.
    public func logBreach(_ input: LogBreachInput) async throws -> LogBreachResult {
        try await request(method: "POST", path: "/api/v1/admin/breach", body: [
            "title": AnyCodable(input.title),
            "description": AnyCodable(input.description),
            "severity": AnyCodable(input.severity.rawValue),
            "affected_user_ids": AnyCodable(input.affectedUserIds),
            "data_categories": AnyCodable(input.dataCategories),
            "reported_by": AnyCodable(input.reportedBy),
        ])
    }

    /// List data breaches.
    ///
    /// - Parameters:
    ///   - status: Optional filter by breach status.
    ///   - limit: Maximum number of results.
    /// - Returns: List of breach records.
    public func listBreaches(status: BreachStatus? = nil, limit: Int? = nil) async throws -> BreachListResult {
        var components: [String] = []
        if let status = status { components.append("status=\(status.rawValue)") }
        if let limit = limit { components.append("limit=\(limit)") }
        let query = components.isEmpty ? "" : "?\(components.joined(separator: "&"))"
        return try await request(method: "GET", path: "/api/v1/admin/breach\(query)")
    }

    /// Get a single breach by ID.
    ///
    /// - Parameter id: Breach ID.
    /// - Returns: The breach record.
    public func getBreach(id: String) async throws -> BreachResult {
        try await request(method: "GET", path: "/api/v1/admin/breach/\(id)")
    }

    /// Update a breach's status.
    ///
    /// - Parameters:
    ///   - id: Breach ID.
    ///   - input: Status update details.
    /// - Returns: The updated breach record.
    public func updateBreachStatus(id: String, _ input: UpdateBreachInput) async throws -> BreachResult {
        var body: [String: AnyCodable] = [
            "status": AnyCodable(input.status.rawValue),
        ]
        if let notificationStatus = input.notificationStatus {
            body["notification_status"] = AnyCodable(notificationStatus.rawValue)
        }
        if let notes = input.notes {
            body["notes"] = AnyCodable(notes)
        }
        return try await request(method: "PATCH", path: "/api/v1/admin/breach/\(id)", body: body)
    }

    // MARK: - Private Helpers

    private static let sdkIdentifier = "Swift SDK"

    /// Resolves the platform string by appending the SDK identifier.
    /// - "iOSApp" → "iOSApp - Swift SDK"
    /// - nil      → "Swift SDK"
    private static func resolvePlatform(_ platform: String?) -> String {
        if let platform = platform, !platform.isEmpty {
            return "\(platform) - \(sdkIdentifier)"
        }
        return sdkIdentifier
    }

    private func contextPayload(_ context: AnalysisContext?) -> ContextPayload {
        ContextPayload(
            language: context?.language,
            ageGroup: context?.ageGroup,
            relationship: context?.relationship,
            platform: Self.resolvePlatform(context?.platform)
        )
    }

    /// Synchronous state update — safe to call from any context.
    private nonisolated func updateMetadata(from httpResponse: HTTPURLResponse, latency: TimeInterval) {
        stateLock.lock()
        defer { stateLock.unlock() }

        _lastLatency = latency
        _lastRequestId = httpResponse.value(forHTTPHeaderField: "X-Request-ID")

        if let limitStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Limit"),
           let limit = Int(limitStr),
           let remainingStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remaining = Int(remainingStr),
           let resetStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let reset = TimeInterval(resetStr) {
            _rateLimitInfo = RateLimitInfo(limit: limit, remaining: remaining, reset: reset)
        }

        if let limitStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Limit"),
           let limit = Int(limitStr),
           let usedStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Used"),
           let used = Int(usedStr),
           let remainingStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Remaining"),
           let remaining = Int(remainingStr) {
            _usage = Usage(
                limit: limit, used: used, remaining: remaining,
                reset: httpResponse.value(forHTTPHeaderField: "X-Monthly-Reset"),
                warning: httpResponse.value(forHTTPHeaderField: "X-Usage-Warning")
            )
        }
    }

    private nonisolated func cachedData(for key: String) -> Data? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let entry = _cache[key], entry.expiry > Date() else { return nil }
        return entry.data
    }

    private nonisolated func setCachedData(_ data: Data, for key: String, ttl: TimeInterval) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _cache[key] = CacheEntry(data: data, expiry: Date().addingTimeInterval(ttl))
    }

    private func encodeBatchItem(_ item: BatchItem) -> BatchItemPayload {
        switch item {
        case .bullying(let id, let text, let context):
            return BatchItemPayload(
                id: id, type: "bullying",
                data: BatchItemData(text: text, context: contextPayload(context))
            )
        case .grooming(let id, let messages, let context):
            return BatchItemPayload(
                id: id, type: "grooming",
                data: BatchItemData(
                    messages: messages.map { ["sender_role": $0.role.rawValue, "text": $0.content] },
                    context: context.map(contextPayload)
                )
            )
        case .unsafe(let id, let text, let context):
            return BatchItemPayload(
                id: id, type: "unsafe",
                data: BatchItemData(text: text, context: contextPayload(context))
            )
        case .emotions(let id, let messages, let context):
            return BatchItemPayload(
                id: id, type: "emotions",
                data: BatchItemData(
                    messages: messages.map { ["sender": $0.sender, "text": $0.content] },
                    context: context.map(contextPayload)
                )
            )
        }
    }

    // MARK: - Request with Encodable body

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (some Encodable)? = nil as Empty?,
        query: [URLQueryItem]? = nil
    ) async throws -> T {
        let bodyData: Data? = try body.map { try encoder.encode($0) }
        return try await requestRetrying(method: method, path: path, bodyData: bodyData, query: query)
    }

    // Overload for GET/DELETE with no body
    private func request<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil
    ) async throws -> T {
        try await requestRetrying(method: method, path: path, bodyData: nil, query: query)
    }

    // Overload for pre-encoded body data
    private func request<T: Decodable>(
        method: String,
        path: String,
        rawBody: Data
    ) async throws -> T {
        try await requestRetrying(method: method, path: path, bodyData: rawBody, query: nil)
    }

    private func requestRetrying<T: Decodable>(
        method: String,
        path: String,
        bodyData: Data?,
        query: [URLQueryItem]?
    ) async throws -> T {
        // Check GET cache
        let cacheKey = method == "GET" && cacheTTL > 0
            ? "\(path)?\(query?.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&") ?? "")"
            : nil
        if let cacheKey = cacheKey, let cached = cachedData(for: cacheKey) {
            return try decoder.decode(T.self, from: cached)
        }

        var lastError: Error?

        for attempt in 0..<maxRetries {
            try Task.checkCancellation()

            do {
                let data = try await performRequest(method: method, path: path, bodyData: bodyData, query: query)

                // Cache GET responses
                if let cacheKey = cacheKey {
                    setCachedData(data, for: cacheKey, ttl: cacheTTL)
                }

                return try decoder.decode(T.self, from: data)
            } catch let error as TuteliqError {
                switch error {
                case .authenticationError, .validationError, .notFoundError, .subscriptionError:
                    throw error
                default:
                    lastError = error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }

            if attempt < maxRetries - 1 {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? TuteliqError.unknownError("Request failed after \(maxRetries) attempts")
    }

    private func performRequest(
        method: String,
        path: String,
        bodyData: Data?,
        query: [URLQueryItem]?
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL.absoluteString + path) else {
            throw TuteliqError.unknownError("Invalid URL path: \(path)")
        }
        if let query = query, !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw TuteliqError.unknownError("Failed to construct URL for: \(path)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if let bodyData = bodyData {
            urlRequest.httpBody = bodyData
        }

        let startTime = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw TuteliqError.timeoutError("Request timed out after \(timeout) seconds")
            case .notConnectedToInternet, .networkConnectionLost:
                throw TuteliqError.networkError("No internet connection")
            default:
                throw TuteliqError.networkError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuteliqError.unknownError("Invalid response")
        }

        updateMetadata(from: httpResponse, latency: Date().timeIntervalSince(startTime))

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "Request failed"

            switch httpResponse.statusCode {
            case 400:
                throw TuteliqError.validationError(message, details: errorResponse?.error.details)
            case 401:
                throw TuteliqError.authenticationError(message)
            case 403:
                throw TuteliqError.subscriptionError(message, code: errorResponse?.error.code)
            case 404:
                throw TuteliqError.notFoundError(message)
            case 429:
                throw TuteliqError.rateLimitError(message)
            case 500...:
                throw TuteliqError.serverError(message, statusCode: httpResponse.statusCode)
            default:
                throw TuteliqError.unknownError(message)
            }
        }

        return data
    }

    // MARK: - Multipart Request

    private func multipartRequest<T: Decodable>(
        path: String,
        body: Data,
        boundary: String
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            try Task.checkCancellation()

            do {
                let data = try await performMultipartRequest(path: path, body: body, boundary: boundary)
                return try decoder.decode(T.self, from: data)
            } catch let error as TuteliqError {
                switch error {
                case .authenticationError, .validationError, .notFoundError, .subscriptionError:
                    throw error
                default:
                    lastError = error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }

            if attempt < maxRetries - 1 {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? TuteliqError.unknownError("Request failed after \(maxRetries) attempts")
    }

    private func performMultipartRequest(
        path: String,
        body: Data,
        boundary: String
    ) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw TuteliqError.unknownError("Invalid URL path: \(path)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let startTime = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw TuteliqError.timeoutError("Request timed out after \(timeout) seconds")
            case .notConnectedToInternet, .networkConnectionLost:
                throw TuteliqError.networkError("No internet connection")
            default:
                throw TuteliqError.networkError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuteliqError.unknownError("Invalid response")
        }

        updateMetadata(from: httpResponse, latency: Date().timeIntervalSince(startTime))

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "Request failed"

            switch httpResponse.statusCode {
            case 400:
                throw TuteliqError.validationError(message, details: errorResponse?.error.details)
            case 401:
                throw TuteliqError.authenticationError(message)
            case 403:
                throw TuteliqError.subscriptionError(message, code: errorResponse?.error.code)
            case 404:
                throw TuteliqError.notFoundError(message)
            case 429:
                throw TuteliqError.rateLimitError(message)
            case 500...:
                throw TuteliqError.serverError(message, statusCode: httpResponse.statusCode)
            default:
                throw TuteliqError.unknownError(message)
            }
        }

        return data
    }

    private static func mimeType(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/m4a"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "webm": return "audio/webm"
        case "mp4": return "audio/mp4"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return nil
        }
    }
}

// MARK: - Multipart Data Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }
}

/// Placeholder type for nil body in generic overload.
private struct Empty: Encodable {}
