import Foundation

/// SafeNest — AI-powered child safety analysis SDK.
///
/// The primary interface for the SafeNest API. Provides methods for detecting
/// bullying, grooming, and unsafe content, as well as emotion analysis,
/// guidance, reports, and platform management.
///
/// ```swift
/// let safenest = try SafeNest(apiKey: "your-api-key")
///
/// let result = try await safenest.detectBullying(content: "message text")
/// if result.isBullying {
///     print("Severity: \(result.severity)")
/// }
/// ```
///
/// All API methods are `async` and the client is thread-safe. It can be shared
/// across tasks and actors. Metadata properties (`usage`, `lastRequestId`,
/// `lastLatency`, `rateLimitInfo`) reflect the most recently completed request.
public final class SafeNest: @unchecked Sendable {

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

    /// Creates a new SafeNest client.
    ///
    /// - Parameters:
    ///   - apiKey: Your SafeNest API key (minimum 10 characters).
    ///   - baseURL: Custom API base URL (defaults to `https://api.safenest.dev`).
    ///   - timeout: Request timeout in seconds (default: 30).
    ///   - maxRetries: Number of retry attempts for transient failures (default: 3).
    ///   - retryDelay: Initial retry delay in seconds, doubled each attempt (default: 1).
    ///   - cacheTTL: Time-to-live for GET response cache in seconds (default: 0 = disabled).
    ///   - session: Custom `URLSession` for advanced configuration or testing.
    /// - Throws: ``SafeNestError/validationError(_:details:)`` if the API key is empty or too short.
    public init(
        apiKey: String,
        baseURL: String = "https://api.safenest.dev",
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1,
        cacheTTL: TimeInterval = 0,
        session: URLSession? = nil
    ) throws {
        guard !apiKey.isEmpty else {
            throw SafeNestError.validationError("API key is required")
        }
        guard apiKey.count >= 10 else {
            throw SafeNestError.validationError("API key appears to be invalid (too short)")
        }
        guard let url = URL(string: baseURL) else {
            throw SafeNestError.validationError("Invalid base URL: \(baseURL)")
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
    /// - Throws: ``SafeNestError`` on failure.
    public func detectBullying(_ input: DetectBullyingInput) async throws -> BullyingResult {
        let body = BullyingRequest(
            text: input.content,
            context: input.context.map(contextPayload),
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
    /// - Throws: ``SafeNestError`` on failure.
    public func detectGrooming(_ input: DetectGroomingInput) async throws -> GroomingResult {
        var ctx = input.context.map(contextPayload) ?? ContextPayload()
        if let childAge = input.childAge { ctx.childAge = childAge }
        let body = GroomingRequest(
            messages: input.messages.map { GroomingMessagePayload(senderRole: $0.role.rawValue, text: $0.content) },
            context: input.childAge != nil || input.context != nil ? ctx : nil,
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
    /// - Throws: ``SafeNestError`` on failure.
    public func detectUnsafe(_ input: DetectUnsafeInput) async throws -> UnsafeResult {
        let body = UnsafeRequest(
            text: input.content,
            context: input.context.map(contextPayload),
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
    /// - Throws: ``SafeNestError`` on failure.
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

        let riskLevel: String
        switch maxRiskScore {
        case 0.9...: riskLevel = RiskLevel.critical.rawValue
        case 0.7..<0.9: riskLevel = RiskLevel.high.rawValue
        case 0.5..<0.7: riskLevel = RiskLevel.medium.rawValue
        case 0.3..<0.5: riskLevel = RiskLevel.low.rawValue
        default: riskLevel = RiskLevel.safe.rawValue
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
    /// - Throws: ``SafeNestError`` on failure.
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
            context: input.context.map(contextPayload),
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
    /// - Throws: ``SafeNestError`` on failure.
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
    /// - Throws: ``SafeNestError`` on failure.
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
    /// - Throws: ``SafeNestError`` on failure. Requires Indie tier or higher.
    public func getPolicy() async throws -> PolicyResult {
        try await request(method: "GET", path: "/api/v1/policy")
    }

    /// Update the policy configuration.
    ///
    /// - Parameter config: New policy configuration dictionary.
    /// - Returns: Updated policy configuration.
    /// - Throws: ``SafeNestError`` on failure. Requires Indie tier or higher.
    public func updatePolicy(_ config: [String: AnyCodable]) async throws -> PolicyResult {
        let body = PolicyUpdateRequest(config: config)
        return try await request(method: "PUT", path: "/api/v1/policy", body: body)
    }

    // MARK: - Batch Analysis

    /// Analyze multiple items in a single request (max 50).
    ///
    /// Use ``BatchResultItem/decodeResult(as:)`` to decode typed results:
    /// ```swift
    /// let batch = try await safenest.batchAnalyze(input)
    /// for item in batch.results where item.success {
    ///     if item.type == "bullying" {
    ///         let result = try item.decodeResult(as: BullyingResult.self)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter input: Batch analysis input with typed items.
    /// - Returns: Individual results and a processing summary.
    /// - Throws: ``SafeNestError`` on failure. Requires Indie tier or higher.
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
    /// - Throws: ``SafeNestError`` on failure. Requires Indie tier or higher.
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

    // MARK: - Private Helpers

    private func contextPayload(_ context: AnalysisContext) -> ContextPayload {
        ContextPayload(
            language: context.language,
            ageGroup: context.ageGroup,
            relationship: context.relationship,
            platform: context.platform
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
                data: BatchItemData(text: text, context: context.map(contextPayload))
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
                data: BatchItemData(text: text, context: context.map(contextPayload))
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
            } catch let error as SafeNestError {
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

        throw lastError ?? SafeNestError.unknownError("Request failed after \(maxRetries) attempts")
    }

    private func performRequest(
        method: String,
        path: String,
        bodyData: Data?,
        query: [URLQueryItem]?
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL.absoluteString + path) else {
            throw SafeNestError.unknownError("Invalid URL path: \(path)")
        }
        if let query = query, !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw SafeNestError.unknownError("Failed to construct URL for: \(path)")
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
                throw SafeNestError.timeoutError("Request timed out after \(timeout) seconds")
            case .notConnectedToInternet, .networkConnectionLost:
                throw SafeNestError.networkError("No internet connection")
            default:
                throw SafeNestError.networkError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SafeNestError.unknownError("Invalid response")
        }

        updateMetadata(from: httpResponse, latency: Date().timeIntervalSince(startTime))

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "Request failed"

            switch httpResponse.statusCode {
            case 400:
                throw SafeNestError.validationError(message, details: errorResponse?.error.details)
            case 401:
                throw SafeNestError.authenticationError(message)
            case 403:
                throw SafeNestError.subscriptionError(message, code: errorResponse?.error.code)
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

        return data
    }
}

/// Placeholder type for nil body in generic overload.
private struct Empty: Encodable {}
