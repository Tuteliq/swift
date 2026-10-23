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
    let baseURL: URL
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
    /// Branch on `result.recommendedAction.isActionable`, not on `isBullying`,
    /// which also fires on low-severity, monitor-only signals.
    ///
    /// ```swift
    /// var input = DetectBullyingInput(content: message)
    /// input.continuationToken = lastToken   // carry trajectory across turns
    /// let result = try await tuteliq.detectBullying(input)
    /// lastToken = result.continuationToken
    /// if result.recommendedAction.isActionable { flag(message) }
    /// ```
    ///
    /// - Parameter input: The bullying detection input.
    /// - Returns: Analysis result with severity, risk score, and recommended action.
    /// - Throws: ``TuteliqError`` on failure.
    public func detectBullying(_ input: DetectBullyingInput) async throws -> BullyingResult {
        try validateContent(input.content)
        let body = TextDetectionRequest(
            text: input.content,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled,
            continuationToken: input.continuationToken,
            resetConversation: input.resetConversation ? true : nil,
            options: DetectionOptions(
                supportThreshold: input.supportThreshold?.rawValue,
                verdictOnly: input.verdictOnly ? true : nil,
                flagProfanity: input.flagProfanity,
                flagRiskTerms: input.flagRiskTerms
            ).nilIfEmpty
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
        try validateMessages(input.messages)
        var ctx = contextPayload(input.context)
        ctx.childAge = input.childAge
        ctx.participantAge = input.participantAge
        let body = GroomingRequest(
            messages: input.messages.map {
                GroomingMessagePayload(senderRole: $0.role.rawValue, text: $0.content, senderAge: $0.senderAge)
            },
            context: ctx,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled,
            continuationToken: input.continuationToken,
            resetConversation: input.resetConversation ? true : nil,
            options: DetectionOptions(
                supportThreshold: input.supportThreshold?.rawValue,
                verdictOnly: input.verdictOnly ? true : nil
            ).nilIfEmpty
        )
        return try await request(method: "POST", path: "/api/v1/safety/grooming", body: body)
    }

    /// Detect unsafe content (self-harm, violence, hate speech, etc.).
    ///
    /// Branch on `result.recommendedAction.isActionable`, not on `unsafe`.
    /// For multi-turn context, pass earlier turns in `context.priorMessages`
    /// or thread `continuationToken` between calls.
    ///
    /// - Parameter input: The unsafe content detection input.
    /// - Returns: Analysis result with categories, severity, and risk score.
    /// - Throws: ``TuteliqError`` on failure.
    public func detectUnsafe(_ input: DetectUnsafeInput) async throws -> UnsafeResult {
        try validateContent(input.content)
        let body = TextDetectionRequest(
            text: input.content,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled,
            continuationToken: input.continuationToken,
            resetConversation: input.resetConversation ? true : nil,
            options: DetectionOptions(
                supportThreshold: input.supportThreshold?.rawValue,
                verdictOnly: input.verdictOnly ? true : nil,
                flagProfanity: input.flagProfanity,
                flagRiskTerms: input.flagRiskTerms
            ).nilIfEmpty
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
            metadata: metadataRaw,
            verdictOnly: input.verdictOnly,
            flagProfanity: input.flagProfanity, flagRiskTerms: input.flagRiskTerms,
            incidentModerationEnabled: input.incidentModerationEnabled
        )
        let unsafeInput = DetectUnsafeInput(
            content: input.content, context: input.context,
            externalId: input.externalId, customerId: input.customerId,
            metadata: metadataRaw,
            verdictOnly: input.verdictOnly,
            flagProfanity: input.flagProfanity, flagRiskTerms: input.flagRiskTerms,
            incidentModerationEnabled: input.incidentModerationEnabled
        )

        async let bullyingTask: BullyingResult? = include.contains(.bullying)
            ? try detectBullying(bullyingInput) : nil
        async let unsafeTask: UnsafeResult? = include.contains(.unsafe)
            ? try detectUnsafe(unsafeInput) : nil

        let (bullyingResult, unsafeResult) = try await (bullyingTask, unsafeTask)

        var maxRiskScore = 0.0
        var maxConfidence = 0.0
        if let b = bullyingResult {
            maxRiskScore = max(maxRiskScore, b.riskScore)
            maxConfidence = max(maxConfidence, b.confidence)
        }
        if let u = unsafeResult {
            maxRiskScore = max(maxRiskScore, u.riskScore)
            maxConfidence = max(maxConfidence, u.confidence)
        }

        let riskLevel: RiskLevel
        switch maxRiskScore {
        case 0.9...: riskLevel = .critical
        case 0.7 ..< 0.9: riskLevel = .high
        case 0.5 ..< 0.7: riskLevel = .medium
        case 0.3 ..< 0.5: riskLevel = .low
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

        // Ranked over the shared enum. The old string matching looked for
        // `flag_for_moderator`, which the API never sends, so `flag_for_review`
        // and `block` verdicts collapsed to `none`.
        let recommendedAction = RecommendedAction.strongest([
            bullyingResult?.recommendedAction, unsafeResult?.recommendedAction,
        ])

        return AnalyzeResult(
            riskLevel: riskLevel, riskScore: maxRiskScore, confidence: maxConfidence, summary: summary,
            bullying: bullyingResult, unsafe: unsafeResult,
            recommendedAction: recommendedAction,
            creditsUsed: nil,
            externalId: input.externalId, customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled
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
            try validateContent(content)
            messages = [EmotionMessagePayload(sender: "user", text: content)]
        } else if let msgs = input.messages {
            try validateMessages(msgs)
            messages = msgs.map { EmotionMessagePayload(sender: $0.sender, text: $0.content) }
        } else {
            throw TuteliqError.validationError("Either content or messages is required")
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
        try validateContent(input.situation, field: "Situation")
        let body = ActionPlanRequest(
            role: (input.audience ?? .parent).rawValue,
            situation: input.situation,
            childAge: input.childAge,
            severity: input.severity?.rawValue,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled
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
        try validateMessages(input.messages)
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
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled
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

    /// Replace the policy configuration.
    ///
    /// Keys use the API's camelCase names:
    /// ```swift
    /// try await tuteliq.setPolicy([
    ///     "bullying": AnyCodable(["enabled": true, "minRiskScoreToFlag": 0.5]),
    /// ])
    /// ```
    ///
    /// - Parameter config: New policy configuration dictionary.
    /// - Returns: Updated policy configuration.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func setPolicy(_ config: [String: AnyCodable]) async throws -> PolicyResult {
        let body = PolicyUpdateRequest(config: config)
        return try await request(method: "PUT", path: "/api/v1/policy", body: body)
    }

    /// The 2.x name of ``setPolicy(_:)``.
    @available(*, deprecated, renamed: "setPolicy(_:)")
    public func updatePolicy(_ config: [String: AnyCodable]) async throws -> PolicyResult {
        try await setPolicy(config)
    }

    // MARK: - Policy Automation Rules

    /// List all policy automation rules for your account.
    public func listPolicyRules() async throws -> ListPolicyRulesResult {
        try await request(method: "GET", path: "/api/v1/policy/automation")
    }

    /// Create a policy automation rule.
    ///
    /// When a detection matches the rule's conditions, its action
    /// (block / flag / escalate / notify / log only) is applied automatically.
    ///
    /// ```swift
    /// let rule = try await tuteliq.createPolicyRule(CreatePolicyRuleInput(
    ///     name: "Escalate critical grooming",
    ///     endpoints: ["grooming"],
    ///     conditions: PolicyRuleConditions(minSeverity: .critical),
    ///     action: PolicyRuleAction(type: .escalate, escalateTo: "safety-team")
    /// ))
    /// ```
    public func createPolicyRule(_ input: CreatePolicyRuleInput) async throws -> PolicyRuleResult {
        try await request(method: "POST", path: "/api/v1/policy/automation", body: input)
    }

    /// Get a single policy automation rule.
    public func getPolicyRule(id: String) async throws -> PolicyRuleResult {
        try await request(method: "GET", path: "/api/v1/policy/automation/\(pathSegment(id, name: "Rule ID"))")
    }

    /// Update a policy automation rule. Only non-nil fields are sent.
    public func updatePolicyRule(id: String, _ input: UpdatePolicyRuleInput) async throws -> PolicyRuleResult {
        try await request(
            method: "PUT", path: "/api/v1/policy/automation/\(pathSegment(id, name: "Rule ID"))", body: input
        )
    }

    /// Delete a policy automation rule.
    public func deletePolicyRule(id: String) async throws -> DeleteResult {
        try await request(method: "DELETE", path: "/api/v1/policy/automation/\(pathSegment(id, name: "Rule ID"))")
    }

    /// Test your rules against a hypothetical detection result without running a detection.
    ///
    /// - Returns: Which rules matched and the winning action after priority resolution.
    public func evaluatePolicyRules(_ input: EvaluatePolicyRulesInput) async throws -> EvaluatePolicyRulesResult {
        try await request(method: "POST", path: "/api/v1/policy/automation/evaluate", body: input)
    }

    // MARK: - Detection Settings

    /// Get the account's detection settings: enabled endpoints, default context,
    /// and the account defaults for `flagProfanity` / `flagRiskTerms`.
    public func getDetectionSettings() async throws -> DetectionSettings {
        try await request(method: "GET", path: "/api/v1/settings/detection")
    }

    /// Update the account's detection settings.
    ///
    /// - Throws: ``TuteliqError/validationError(_:details:)`` if both
    ///   `enabledEndpoints` and `disabledEndpoints` are set.
    public func updateDetectionSettings(_ input: UpdateDetectionSettingsInput) async throws -> UpdateDetectionSettingsResult {
        if input.enabledEndpoints != nil, input.disabledEndpoints != nil {
            throw TuteliqError.validationError("enabledEndpoints and disabledEndpoints are mutually exclusive")
        }
        return try await request(method: "PUT", path: "/api/v1/settings/detection", body: input)
    }

    /// Reset detection settings to their defaults (all endpoints enabled).
    public func resetDetectionSettings() async throws -> SuccessMessageResult {
        try await request(method: "DELETE", path: "/api/v1/settings/detection")
    }

    // MARK: - Threat Intelligence

    /// Anonymised threat intelligence trends across the Tuteliq network. Requires Business tier or higher.
    public func getIntelligenceTrends(_ options: IntelligenceTrendsOptions = IntelligenceTrendsOptions()) async throws -> IntelligenceTrendsResult {
        var query: [URLQueryItem] = []
        if let v = options.days {
            query.append(URLQueryItem(name: "days", value: "\(v)"))
        }
        if let v = options.endpoint {
            query.append(URLQueryItem(name: "endpoint", value: v))
        }
        if let v = options.ageGroup {
            query.append(URLQueryItem(name: "age_group", value: v))
        }
        if let v = options.platform {
            query.append(URLQueryItem(name: "platform", value: v))
        }
        return try await request(method: "GET", path: "/api/v1/intelligence/trends", query: query)
    }

    /// Emerging threats over a recent window (default 7 days, max 90). Requires Business tier or higher.
    public func getEmergingThreats(days: Int? = nil) async throws -> EmergingThreatsResult {
        try await request(method: "GET", path: "/api/v1/intelligence/emerging", query: daysQuery(days))
    }

    /// The weekly threat intelligence digest. Requires Business tier or higher.
    public func getWeeklyDigest() async throws -> WeeklyDigestResult {
        try await request(method: "GET", path: "/api/v1/intelligence/weekly-digest")
    }

    /// Anonymised global risk trends (1–90 days, default 30). Requires Business tier or higher.
    public func getRiskTrends(days: Int? = nil) async throws -> RiskTrendsResult {
        try await request(method: "GET", path: "/api/v1/safety/risk-trends", query: daysQuery(days))
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
        guard !input.items.isEmpty else {
            throw TuteliqError.validationError("Items array is required and cannot be empty")
        }
        guard input.items.count <= 50 else {
            throw TuteliqError.validationError("Maximum 50 items per batch request")
        }
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
        if let date = date {
            query = [URLQueryItem(name: "date", value: date)]
        }
        return try await request(method: "GET", path: "/api/v1/usage/summary", query: query)
    }

    /// Get usage history for the past N days.
    ///
    /// - Parameter days: Number of days (1-30, defaults to 7).
    /// - Returns: Daily request counts.
    public func getUsageHistory(days: Int? = nil) async throws -> UsageHistoryResult {
        var query: [URLQueryItem]?
        if let days = days {
            query = [URLQueryItem(name: "days", value: "\(days)")]
        }
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
        if let date = date {
            query = [URLQueryItem(name: "date", value: date)]
        }
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
        return try await request(method: "PUT", path: "/api/v1/webhooks/\(pathSegment(id, name: "Webhook ID"))", body: body)
    }

    /// Delete a webhook.
    ///
    /// - Parameter id: Webhook ID.
    /// - Returns: Confirmation of deletion.
    public func deleteWebhook(id: String) async throws -> DeleteResult {
        try await request(method: "DELETE", path: "/api/v1/webhooks/\(pathSegment(id, name: "Webhook ID"))")
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
        try await request(method: "POST", path: "/api/v1/webhooks/\(pathSegment(id, name: "Webhook ID"))/regenerate-secret")
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

        let mimeType = Self.mimeType(forFilename: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.analysisType {
            body.appendMultipartField(boundary: boundary, name: "analysis_type", value: v.rawValue)
        }
        if let v = input.fileId {
            body.appendMultipartField(boundary: boundary, name: "file_id", value: v)
        }
        if let v = input.externalId {
            body.appendMultipartField(boundary: boundary, name: "external_id", value: v)
        }
        if let v = input.customerId {
            body.appendMultipartField(boundary: boundary, name: "customer_id", value: v)
        }
        if let v = input.ageGroup {
            body.appendMultipartField(boundary: boundary, name: "age_group", value: v)
        }
        if let v = input.language {
            body.appendMultipartField(boundary: boundary, name: "language", value: v)
        }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let v = input.childAge {
            body.appendMultipartField(boundary: boundary, name: "child_age", value: "\(v)")
        }
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
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

        let mimeType = Self.mimeType(forFilename: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.analysisType {
            body.appendMultipartField(boundary: boundary, name: "analysis_type", value: v.rawValue)
        }
        if let v = input.fileId {
            body.appendMultipartField(boundary: boundary, name: "file_id", value: v)
        }
        if let v = input.externalId {
            body.appendMultipartField(boundary: boundary, name: "external_id", value: v)
        }
        if let v = input.customerId {
            body.appendMultipartField(boundary: boundary, name: "customer_id", value: v)
        }
        if let v = input.ageGroup {
            body.appendMultipartField(boundary: boundary, name: "age_group", value: v)
        }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }

        if let v = input.flagProfanity {
            body.appendMultipartField(boundary: boundary, name: "flag_profanity", value: "\(v)")
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/safety/image", body: body, boundary: boundary)
    }

    // MARK: - Fraud Detection

    /// Detect social engineering tactics.
    public func detectSocialEngineering(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/fraud/social-engineering", body: buildDetectionRequest(input))
    }

    /// Detect app-based fraud patterns.
    public func detectAppFraud(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/fraud/app-fraud", body: buildDetectionRequest(input))
    }

    /// Detect romance scam patterns.
    public func detectRomanceScam(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/fraud/romance-scam", body: buildDetectionRequest(input))
    }

    /// Detect money mule recruitment.
    public func detectMuleRecruitment(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/fraud/mule-recruitment", body: buildDetectionRequest(input))
    }

    // MARK: - Safety Extended

    /// Detect gambling harm indicators.
    public func detectGamblingHarm(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/gambling-harm", body: buildDetectionRequest(input))
    }

    /// Detect coercive control patterns.
    public func detectCoerciveControl(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/coercive-control", body: buildDetectionRequest(input))
    }

    /// Detect vulnerability exploitation with cross-endpoint modifier.
    public func detectVulnerabilityExploitation(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/vulnerability-exploitation", body: buildDetectionRequest(input))
    }

    /// Detect radicalisation indicators.
    public func detectRadicalisation(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/radicalisation", body: buildDetectionRequest(input))
    }

    /// Detect linguistic distress-signal patterns (loneliness, isolation, hopelessness, trust-seeking openers).
    ///
    /// Framed as content classification rather than inner-state emotion inference
    /// (EU AI Act Art 5(1)(f)). Conversation-aware: thread `continuationToken` between calls.
    public func detectDistressSignals(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/distress-signals", body: buildDetectionRequest(input))
    }

    /// Detect technology-facilitated gender-based violence: image-based abuse, cyberstalking,
    /// doxing, outing, post-separation abuse, digital coercion and sexualised deepfakes.
    public func detectTFGBV(_ input: DetectionInput) async throws -> DetectionResult {
        try await request(method: "POST", path: "/api/v1/safety/tfgbv", body: buildDetectionRequest(input))
    }

    // MARK: - Multi-Endpoint Analysis

    /// Run multiple detection endpoints on a single piece of content.
    ///
    /// When vulnerability-exploitation is included, its cross-endpoint modifier
    /// automatically adjusts severity scores across all other results.
    public func analyseMulti(_ input: AnalyseMultiInput) async throws -> AnalyseMultiResult {
        try validateContent(input.content)
        guard !input.detections.isEmpty else {
            throw TuteliqError.validationError("At least one detection endpoint is required")
        }
        guard input.detections.count <= 10 else {
            throw TuteliqError.validationError("Maximum 10 detection endpoints per request")
        }
        let body = AnalyseMultiRequest(
            text: input.content,
            endpoints: input.detections.map(\.rawValue),
            context: contextPayload(input.context),
            options: DetectionOptions(
                supportThreshold: input.supportThreshold?.rawValue,
                includeEvidence: input.includeEvidence ? true : nil,
                verdictOnly: input.verdictOnly ? true : nil
            ).nilIfEmpty,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled
        )
        return try await request(method: "POST", path: "/api/v1/analyse/multi", body: body)
    }

    // MARK: - Video Analysis

    /// Analyze video content for safety concerns.
    ///
    /// Extracts frames and analyzes them for harmful visual content.
    /// Supported formats: mp4, webm, quicktime, x-msvideo.
    public func analyzeVideo(_ input: AnalyzeVideoInput) async throws -> VideoAnalysisResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        let mimeType = Self.mimeType(forFilename: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.fileId {
            body.appendMultipartField(boundary: boundary, name: "file_id", value: v)
        }
        if let v = input.externalId {
            body.appendMultipartField(boundary: boundary, name: "external_id", value: v)
        }
        if let v = input.customerId {
            body.appendMultipartField(boundary: boundary, name: "customer_id", value: v)
        }
        if let v = input.ageGroup {
            body.appendMultipartField(boundary: boundary, name: "age_group", value: v)
        }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }

        if let v = input.flagProfanity {
            body.appendMultipartField(boundary: boundary, name: "flag_profanity", value: "\(v)")
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/safety/video", body: body, boundary: boundary)
    }

    // MARK: - Document Analysis

    /// Analyze a PDF document for safety concerns.
    ///
    /// Extracts text from each page (via text layer or OCR) and runs the specified
    /// detection endpoints on every page. Supported format: PDF (max 50MB).
    ///
    /// ```swift
    /// let pdfData = try Data(contentsOf: pdfURL)
    /// let input = AnalyzeDocumentInput(
    ///     file: pdfData,
    ///     filename: "report.pdf",
    ///     endpoints: [.unsafe, .coerciveControl, .radicalisation]
    /// )
    /// let result = try await tuteliq.analyzeDocument(input)
    /// print("Risk: \(result.overallSeverity)")
    /// print("Flagged pages: \(result.flaggedPages.count)")
    /// print("Credits: \(result.creditsUsed)")
    /// ```
    ///
    /// - Parameter input: Document analysis input with PDF file data.
    /// - Returns: Per-page detection results with overall risk assessment.
    /// - Throws: ``TuteliqError`` on failure. Requires Indie tier or higher.
    public func analyzeDocument(_ input: AnalyzeDocumentInput) async throws -> DocumentAnalysisResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        let mimeType = Self.mimeType(forFilename: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let endpoints = input.endpoints {
            let endpointStrings = endpoints.map(\.rawValue)
            if let jsonData = try? JSONSerialization.data(withJSONObject: endpointStrings),
               let jsonString = String(data: jsonData, encoding: .utf8)
            {
                body.appendMultipartField(boundary: boundary, name: "endpoints", value: jsonString)
            }
        }
        if let v = input.fileId {
            body.appendMultipartField(boundary: boundary, name: "file_id", value: v)
        }
        if let v = input.externalId {
            body.appendMultipartField(boundary: boundary, name: "external_id", value: v)
        }
        if let v = input.customerId {
            body.appendMultipartField(boundary: boundary, name: "customer_id", value: v)
        }
        if let v = input.ageGroup {
            body.appendMultipartField(boundary: boundary, name: "age_group", value: v)
        }
        if let v = input.language {
            body.appendMultipartField(boundary: boundary, name: "language", value: v)
        }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let v = input.supportThreshold {
            body.appendMultipartField(boundary: boundary, name: "support_threshold", value: v.rawValue)
        }
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/safety/document", body: body, boundary: boundary)
    }

    // MARK: - Synthetic Content Detection

    /// Detect AI-generated or synthetic text (LLM output, synthetic identities, AI-enhanced grooming scripts).
    public func detectSyntheticText(_ input: DetectSyntheticTextInput) async throws -> SyntheticTextResult {
        try validateContent(input.content)
        let body = SyntheticTextRequest(
            text: input.content,
            context: contextPayload(input.context),
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled,
            bypassCache: input.bypassCache ? true : nil,
            options: DetectionOptions(supportThreshold: input.supportThreshold?.rawValue).nilIfEmpty
        )
        return try await request(method: "POST", path: "/api/v1/safety/synthetic-content", body: body)
    }

    /// Detect AI-generated images with a multi-signal forensic pipeline
    /// (vision, EXIF, pixel statistics, C2PA, watermarks, perceptual hash).
    ///
    /// ```swift
    /// let result = try await tuteliq.detectSyntheticImage(
    ///     DetectSyntheticMediaInput(file: jpegData, filename: "photo.jpg")
    /// )
    /// if result.classification == .confirmedSynthetic { ... }
    /// ```
    public func detectSyntheticImage(_ input: DetectSyntheticMediaInput) async throws -> SyntheticImageResult {
        try await syntheticMediaRequest(input, path: "/api/v1/safety/synthetic-content/image")
    }

    /// Detect AI-generated or cloned voice audio with spectral forensics.
    public func detectSyntheticAudio(_ input: DetectSyntheticMediaInput) async throws -> SyntheticAudioResult {
        try await syntheticMediaRequest(input, path: "/api/v1/safety/synthetic-content/audio")
    }

    /// Detect deepfakes and AI-generated video with temporal face consistency and lip-sync analysis.
    public func detectSyntheticVideo(_ input: DetectSyntheticMediaInput) async throws -> SyntheticVideoResult {
        try await syntheticMediaRequest(input, path: "/api/v1/safety/synthetic-content/video")
    }

    private func syntheticMediaRequest<T: Decodable>(_ input: DetectSyntheticMediaInput, path: String) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        let mimeType = Self.mimeType(forFilename: input.filename) ?? "application/octet-stream"
        body.appendMultipart(boundary: boundary, name: "file", filename: input.filename, mimeType: mimeType, data: input.file)

        if let v = input.maxFrames {
            body.appendMultipartField(boundary: boundary, name: "max_frames", value: "\(v)")
        }
        if let v = input.ageGroup {
            body.appendMultipartField(boundary: boundary, name: "age_group", value: v)
        }
        if let v = input.language {
            body.appendMultipartField(boundary: boundary, name: "language", value: v)
        }
        if let v = input.externalId {
            body.appendMultipartField(boundary: boundary, name: "external_id", value: v)
        }
        if let v = input.customerId {
            body.appendMultipartField(boundary: boundary, name: "customer_id", value: v)
        }
        body.appendMultipartField(boundary: boundary, name: "platform", value: Self.resolvePlatform(input.platform))
        if let metadata = input.metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            body.appendMultipartField(boundary: boundary, name: "metadata", value: jsonString)
        }
        if input.bypassCache {
            body.appendMultipartField(boundary: boundary, name: "bypass_cache", value: "true")
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: path, body: body, boundary: boundary)
    }

    // MARK: - Verification

    /// Create a verification session.
    ///
    /// ```swift
    /// let input = CreateVerificationSessionInput(mode: .age, documentType: .passport)
    /// let session = try await tuteliq.createVerificationSession(input)
    /// print("Open URL:", session.url)
    /// ```
    ///
    /// - Parameter input: Session configuration with mode and optional document type.
    /// - Returns: A `VerificationSession` with URL to redirect user.
    public func createVerificationSession(_ input: CreateVerificationSessionInput) async throws -> VerificationSession {
        var body = CreateVerificationSessionRequest(mode: input.mode.rawValue)
        body.documentType = input.documentType?.rawValue
        return try await request(method: "POST", path: "/api/v1/verify/session", body: body)
    }

    /// Get the current status of a verification session.
    ///
    /// Poll this endpoint after creating a session to check completion.
    ///
    /// - Parameter id: The session ID from `createVerificationSession`.
    /// - Returns: A `VerificationSessionResult` with current status.
    public func getVerificationSession(id: String) async throws -> VerificationSessionResult {
        return try await request(method: "GET", path: "/api/v1/verify/session/\(pathSegment(id, name: "Session ID"))")
    }

    /// Cancel a verification session. The session moves to `expired` and any
    /// staged document images are purged.
    ///
    /// - Parameter id: The session ID to cancel.
    /// - Returns: A `CancelVerificationSessionResult` (`ok: true`).
    public func cancelVerificationSession(id: String) async throws -> CancelVerificationSessionResult {
        return try await request(method: "DELETE", path: "/api/v1/verify/session/\(pathSegment(id, name: "Session ID"))")
    }

    /// Retrieve a past age verification result.
    ///
    /// - Parameter id: The verification ID.
    /// - Returns: A `VerificationRetrieveResult` with verification details.
    public func getAgeVerification(id: String) async throws -> VerificationRetrieveResult {
        return try await request(method: "GET", path: "/api/v1/verify/age/\(pathSegment(id, name: "Verification ID"))")
    }

    /// Retrieve a past identity verification result.
    ///
    /// - Parameter id: The verification ID.
    /// - Returns: An `IdentityRetrieveResult` with verification details.
    public func getIdentityVerification(id: String) async throws -> IdentityRetrieveResult {
        return try await request(method: "GET", path: "/api/v1/verify/identity/\(pathSegment(id, name: "Verification ID"))")
    }

    /// Get a server-signed liveness challenge.
    ///
    /// Returns a `LivenessChallenge` whose `challenges` array prescribes the
    /// order in which the client must run the prompts (e.g. `"center"`,
    /// `"left"`, `"right"`, `"blink"`, `"smile"`). The signature is bound to
    /// that order — re-ordering will fail server-side validation.
    ///
    /// The endpoint is server-side public (no auth required); the SDK still
    /// sends its Bearer header, which the server simply ignores.
    ///
    /// - Returns: A `LivenessChallenge` valid for ~5 minutes.
    public func getLivenessChallenge() async throws -> LivenessChallenge {
        return try await request(method: "GET", path: "/api/v1/verify/age/challenge")
    }

    /// Submit verification documents for processing.
    ///
    /// Wraps `POST /api/v1/verify/submit`. Provide either a passport image
    /// **or** an ID front + back. Selfie and `livenessToken` are required.
    ///
    /// ```swift
    /// let challenge = try await tuteliq.getLivenessChallenge()
    /// // ... run challenges in order, build a liveness token JSON ...
    /// let input = SubmitVerificationInput(
    ///     passport: passportJPEG,
    ///     selfie: selfieJPEG,
    ///     livenessToken: tokenJSON,
    ///     livenessFrames: capturedFrames
    /// )
    /// let result = try await tuteliq.submitVerification(input)
    /// ```
    ///
    /// - Parameter input: Document buffers, selfie, liveness token, optional frames.
    /// - Returns: A `VerificationSubmitResult` with status, age, document fields, face match, liveness.
    public func submitVerification(_ input: SubmitVerificationInput) async throws -> VerificationSubmitResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        if let data = input.passport {
            body.appendMultipart(boundary: boundary, name: "passport", filename: "passport.jpg", mimeType: "image/jpeg", data: data)
        }
        if let data = input.idFront {
            body.appendMultipart(boundary: boundary, name: "id_front", filename: "id_front.jpg", mimeType: "image/jpeg", data: data)
        }
        if let data = input.idBack {
            body.appendMultipart(boundary: boundary, name: "id_back", filename: "id_back.jpg", mimeType: "image/jpeg", data: data)
        }
        body.appendMultipart(boundary: boundary, name: "selfie", filename: "selfie.jpg", mimeType: "image/jpeg", data: input.selfie)
        body.appendMultipartField(boundary: boundary, name: "liveness_token", value: input.livenessToken)

        if let frames = input.livenessFrames {
            for (idx, frame) in frames.enumerated() {
                body.appendMultipart(
                    boundary: boundary,
                    name: "liveness_frame",
                    filename: "frame-\(idx).jpg",
                    mimeType: "image/jpeg",
                    data: frame
                )
            }
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await multipartRequest(path: "/api/v1/verify/submit", body: body, boundary: boundary)
    }

    // MARK: - Voice Streaming

    /// Create a voice streaming session over WebSocket.
    ///
    /// Uses `URLSessionWebSocketTask` — no external dependencies required.
    ///
    /// ```swift
    /// let session = tuteliq.voiceStream(
    ///     config: VoiceStreamConfig(intervalSeconds: 10, analysisTypes: ["bullying", "unsafe"]),
    ///     handlers: VoiceStreamHandlers(
    ///         onTranscription: { print("Transcript:", $0.text) },
    ///         onAlert: { print("Alert:", $0.category, $0.severity) }
    ///     )
    /// )
    /// try await session.connect()
    /// try session.sendAudio(audioData)
    /// let summary = try await session.end()
    /// ```
    ///
    /// - Parameters:
    ///   - config: Optional session configuration.
    ///   - handlers: Optional event handler callbacks.
    /// - Returns: A `VoiceStreamSession`. Call `connect()` to start.
    public func voiceStream(
        config: VoiceStreamConfig? = nil,
        handlers: VoiceStreamHandlers = VoiceStreamHandlers()
    ) -> VoiceStreamSession {
        VoiceStreamSession(
            apiKey: apiKey,
            config: config,
            handlers: handlers
        )
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
        if let action = action {
            components.append("action=\(action.rawValue)")
        }
        if let limit = limit {
            components.append("limit=\(limit)")
        }
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
        if let status = status {
            components.append("status=\(status.rawValue)")
        }
        if let limit = limit {
            components.append("limit=\(limit)")
        }
        let query = components.isEmpty ? "" : "?\(components.joined(separator: "&"))"
        return try await request(method: "GET", path: "/api/v1/admin/breach\(query)")
    }

    /// Get a single breach by ID.
    ///
    /// - Parameter id: Breach ID.
    /// - Returns: The breach record.
    public func getBreach(id: String) async throws -> BreachResult {
        try await request(method: "GET", path: "/api/v1/admin/breach/\(pathSegment(id, name: "Breach ID"))")
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
        return try await request(method: "PATCH", path: "/api/v1/admin/breach/\(pathSegment(id, name: "Breach ID"))", body: body)
    }

    // MARK: - Customer-Managed Encryption Keys

    /// Register (or rotate) the RSA public key used to encrypt your incident records.
    ///
    /// New incident rationale, visual description, source data and metadata are
    /// wrapped with a per-record AES-256-GCM key, itself encrypted with this RSA-OAEP
    /// key. Tuteliq cannot decrypt them, and cannot recover incidents if you lose the private key.
    public func registerEncryptionKey(_ input: RegisterEncryptionKeyInput) async throws -> CustomerEncryptionKey {
        try await request(method: "POST", path: "/api/v1/account/encryption-key", body: input)
    }

    /// The currently registered public key, or `nil` when none is registered
    /// (incidents then use server-side encryption with a Tuteliq-held key).
    public func getEncryptionKey() async throws -> CustomerEncryptionKey? {
        do {
            return try await request(method: "GET", path: "/api/v1/account/encryption-key") as CustomerEncryptionKey
        } catch TuteliqError.notFoundError {
            return nil
        }
    }

    /// Revoke the registered public key. New incidents fall back to server-side encryption;
    /// existing ones stay readable only with the prior key.
    public func revokeEncryptionKey() async throws -> RevokeEncryptionKeyResult {
        try await request(method: "DELETE", path: "/api/v1/account/encryption-key")
    }

    // MARK: - Audit Receipts (EU AI Act Art 12)

    /// Fetch the signed audit receipt for a past request.
    ///
    /// Only the API key that produced the receipt can fetch it; any other gets a 404.
    /// - Parameter requestId: The request ID (see ``lastRequestId``).
    public func getAuditReceipt(requestId: String) async throws -> AuditReceipt {
        try await request(method: "GET", path: "/api/v1/audit/receipts/\(pathSegment(requestId, name: "Request ID"))")
    }

    // MARK: - Incident Review (EU AI Act Art 14)

    /// Submit a moderator review of an incident.
    ///
    /// Persists the override (keeping the original classification) and emits a
    /// signed audit receipt linked to the incident.
    public func reviewIncident(id: String, _ input: ReviewIncidentInput) async throws -> ReviewIncidentResult {
        if input.action == .reclassify, input.newRiskCategory == nil {
            throw TuteliqError.validationError("action reclassify requires newRiskCategory")
        }
        return try await request(
            method: "POST", path: "/api/v1/incidents/\(pathSegment(id, name: "Incident ID"))/review", body: input
        )
    }

    /// Apply the same review to up to 100 incidents.
    ///
    /// Each incident still gets its own audit receipt. Per-incident failures are
    /// non-fatal; retry the entries in `results` where `ok` is false.
    public func batchReviewIncidents(_ input: BatchReviewIncidentsInput) async throws -> BatchReviewIncidentsResult {
        guard !input.incidentIds.isEmpty else {
            throw TuteliqError.validationError("incidentIds must be a non-empty array")
        }
        guard input.incidentIds.count <= 100 else {
            throw TuteliqError.validationError("batchReviewIncidents accepts at most 100 incidents per call")
        }
        if input.action == .reclassify, input.newRiskCategory == nil {
            throw TuteliqError.validationError("action reclassify requires newRiskCategory")
        }
        return try await request(method: "POST", path: "/api/v1/incidents/batch-review", body: input)
    }

    // MARK: - Incidents Dashboard

    /// Paginated, filterable listing of your incidents, newest first.
    ///
    /// ```swift
    /// var cursor: String?
    /// repeat {
    ///     let page = try await tuteliq.listIncidents(ListIncidentsInput(severity: .critical, cursor: cursor))
    ///     page.incidents.forEach { print($0.id, $0.riskLevel) }
    ///     cursor = page.nextCursor
    /// } while cursor != nil
    /// ```
    public func listIncidents(_ input: ListIncidentsInput = ListIncidentsInput()) async throws -> ListIncidentsResult {
        var query: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value = value {
                query.append(URLQueryItem(name: name, value: value))
            }
        }
        add("category", input.category)
        add("severity", input.severity?.rawValue)
        add("status", input.status?.rawValue)
        add("source", input.source?.rawValue)
        add("from", input.from)
        add("to", input.to)
        add("platform", input.platform)
        add("external_id", input.externalId)
        add("customer_id", input.customerId)
        add("limit", input.limit.map { "\($0)" })
        add("cursor", input.cursor)
        if input.includeSummary {
            add("include_summary", "true")
        }
        return try await request(method: "GET", path: "/api/v1/incidents", query: query)
    }

    /// A single incident's full detail. BYOK-encrypted fields are listed in `e2eEnvelopeFields`.
    public func getIncident(id: String) async throws -> IncidentDetail {
        try await request(method: "GET", path: "/api/v1/incidents/\(pathSegment(id, name: "Incident ID"))")
    }

    /// KPI overview of incidents over a window (default: the last 30 days).
    /// - Parameters:
    ///   - from: ISO 8601 inclusive lower bound.
    ///   - to: ISO 8601 exclusive upper bound.
    public func getIncidentsOverview(from: String? = nil, to: String? = nil) async throws -> IncidentsOverview {
        var query: [URLQueryItem] = []
        if let from = from {
            query.append(URLQueryItem(name: "from", value: from))
        }
        if let to = to {
            query.append(URLQueryItem(name: "to", value: to))
        }
        return try await request(method: "GET", path: "/api/v1/incidents/overview", query: query)
    }

    /// Time-bucketed incident counts with a per-bucket severity breakdown (default: daily, last 30 days).
    public func getIncidentTrends(
        bucket: IncidentTrendBucketSize? = nil, from: String? = nil, to: String? = nil
    ) async throws -> IncidentTrends {
        var query: [URLQueryItem] = []
        if let bucket = bucket {
            query.append(URLQueryItem(name: "bucket", value: bucket.rawValue))
        }
        if let from = from {
            query.append(URLQueryItem(name: "from", value: from))
        }
        if let to = to {
            query.append(URLQueryItem(name: "to", value: to))
        }
        return try await request(method: "GET", path: "/api/v1/incidents/trends", query: query)
    }

    // MARK: - Secure API Key Storage (Keychain)

    #if canImport(Security)
        /// Store an API key securely in the system Keychain.
        ///
        /// Use this method at first launch or after the user enters their key,
        /// then create clients with ``withStoredAPIKey(service:baseURL:timeout:maxRetries:retryDelay:cacheTTL:session:)``.
        ///
        /// ```swift
        /// // Store once (e.g. after onboarding)
        /// try Tuteliq.storeAPIKey("sk_live_abc123...")
        ///
        /// // Later, create a client from the stored key
        /// let tuteliq = try Tuteliq.withStoredAPIKey()
        /// ```
        ///
        /// - Parameters:
        ///   - apiKey: The Tuteliq API key to store.
        ///   - service: Keychain service identifier (default: `ai.tuteliq.api-key`).
        /// - Throws: ``TuteliqError/validationError(_:details:)`` if the Keychain operation fails.
        public static func storeAPIKey(_ apiKey: String, service: String = "ai.tuteliq.api-key") throws {
            try KeychainStore.save(apiKey: apiKey, service: service)
        }

        /// Remove the stored API key from the system Keychain.
        ///
        /// - Parameter service: Keychain service identifier (default: `ai.tuteliq.api-key`).
        /// - Throws: ``TuteliqError/validationError(_:details:)`` if the Keychain operation fails.
        public static func removeAPIKey(service: String = "ai.tuteliq.api-key") throws {
            try KeychainStore.delete(service: service)
        }

        /// Read the API key from `Bundle.main.infoDictionary` and store it in the Keychain.
        ///
        /// This is the recommended way to bootstrap your API key at app launch.
        /// Set the key in an `.xcconfig` file (git-ignored) and reference it in
        /// `Info.plist` — then call this method once on startup:
        ///
        /// ```swift
        /// try Tuteliq.configure()  // reads TuteliqAPIKey from Info.plist → Keychain
        /// let client = try Tuteliq.withStoredAPIKey()
        /// ```
        ///
        /// - Parameters:
        ///   - bundleKey: The key to look up in `Bundle.main.infoDictionary` (default: `"TuteliqAPIKey"`).
        ///   - service: Keychain service identifier (default: `"ai.tuteliq.api-key"`).
        /// - Throws: ``TuteliqError/validationError(_:details:)`` if the key is missing from the bundle
        ///   or cannot be stored in the Keychain.
        public static func configure(
            fromBundleKey bundleKey: String = "TuteliqAPIKey",
            service: String = "ai.tuteliq.api-key"
        ) throws {
            guard let apiKey = Bundle.main.infoDictionary?[bundleKey] as? String,
                  !apiKey.isEmpty
            else {
                throw TuteliqError.validationError(
                    "No API key found in Info.plist for key \"\(bundleKey)\". "
                        + "Add it via an .xcconfig file or set it directly in your target's Info.plist."
                )
            }
            try KeychainStore.save(apiKey: apiKey, service: service)
        }

        /// Create a Tuteliq client using an API key stored in the Keychain.
        ///
        /// ```swift
        /// let tuteliq = try Tuteliq.withStoredAPIKey()
        /// let result = try await tuteliq.detectBullying(content: "hello")
        /// ```
        ///
        /// - Parameters:
        ///   - service: Keychain service identifier (default: `ai.tuteliq.api-key`).
        ///   - baseURL: Custom API base URL (defaults to `https://api.tuteliq.ai`).
        ///   - timeout: Request timeout in seconds (default: 30).
        ///   - maxRetries: Number of retry attempts for transient failures (default: 3).
        ///   - retryDelay: Initial retry delay in seconds, doubled each attempt (default: 1).
        ///   - cacheTTL: Time-to-live for GET response cache in seconds (default: 0 = disabled).
        ///   - session: Custom `URLSession` for advanced configuration or testing.
        /// - Returns: A configured ``Tuteliq`` client.
        /// - Throws: ``TuteliqError/validationError(_:details:)`` if no key is found or it is invalid.
        public static func withStoredAPIKey(
            service: String = "ai.tuteliq.api-key",
            baseURL: String = "https://api.tuteliq.ai",
            timeout: TimeInterval = 30,
            maxRetries: Int = 3,
            retryDelay: TimeInterval = 1,
            cacheTTL: TimeInterval = 0,
            session: URLSession? = nil
        ) throws -> Tuteliq {
            guard let apiKey = KeychainStore.retrieve(service: service) else {
                throw TuteliqError.validationError(
                    "No API key found in Keychain. Call Tuteliq.storeAPIKey(_:) first."
                )
            }
            return try Tuteliq(
                apiKey: apiKey,
                baseURL: baseURL,
                timeout: timeout,
                maxRetries: maxRetries,
                retryDelay: retryDelay,
                cacheTTL: cacheTTL,
                session: session
            )
        }
    #endif

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
            platform: Self.resolvePlatform(context?.platform),
            country: context?.country,
            priorMessages: context?.priorMessages
        )
    }

    private func buildDetectionRequest(_ input: DetectionInput) throws -> DetectionRequest {
        try validateContent(input.content)
        // `includeEvidence` is forwarded on true AND false, and omitted only when
        // unset, so the server can apply its own default (false under verdictOnly).
        return DetectionRequest(
            text: input.content,
            context: contextPayload(input.context),
            includeEvidence: input.includeEvidence,
            continuationToken: input.continuationToken,
            resetConversation: input.resetConversation ? true : nil,
            externalId: input.externalId,
            customerId: input.customerId,
            metadata: input.metadata,
            incidentModerationEnabled: input.incidentModerationEnabled,
            options: DetectionOptions(
                supportThreshold: input.supportThreshold?.rawValue,
                includeEvidence: input.includeEvidence,
                verdictOnly: input.verdictOnly ? true : nil
            ).nilIfEmpty
        )
    }

    private static let maxContentLength = 50000
    private static let maxMessagesCount = 100

    private func validateContent(_ content: String, field: String = "Content") throws {
        guard !content.isEmpty else {
            throw TuteliqError.validationError("\(field) is required")
        }
        guard content.count <= Self.maxContentLength else {
            throw TuteliqError.validationError("\(field) exceeds maximum length of \(Self.maxContentLength) characters")
        }
    }

    private func validateMessages<T>(_ messages: [T]) throws {
        guard !messages.isEmpty else {
            throw TuteliqError.validationError("Messages array is required and cannot be empty")
        }
        guard messages.count <= Self.maxMessagesCount else {
            throw TuteliqError.validationError("Messages array exceeds maximum count of \(Self.maxMessagesCount)")
        }
    }

    /// Percent-encodes an ID for use as one path segment.
    private func pathSegment(_ value: String, name: String) throws -> String {
        guard !value.isEmpty else { throw TuteliqError.validationError("\(name) is required") }
        // A dot segment is resolved by the URL, not sent as an ID.
        guard value != ".", value != ".." else { throw TuteliqError.validationError("\(name) is not valid") }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func daysQuery(_ days: Int?) -> [URLQueryItem] {
        days.map { [URLQueryItem(name: "days", value: "\($0)")] } ?? []
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
           let reset = TimeInterval(resetStr)
        {
            _rateLimitInfo = RateLimitInfo(limit: limit, remaining: remaining, reset: reset)
        }

        if let limitStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Limit"),
           let limit = Int(limitStr),
           let usedStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Used"),
           let used = Int(usedStr),
           let remainingStr = httpResponse.value(forHTTPHeaderField: "X-Monthly-Remaining"),
           let remaining = Int(remainingStr)
        {
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
        case let .bullying(id, text, context):
            return BatchItemPayload(
                id: id, type: "bullying",
                data: BatchItemData(text: text, context: contextPayload(context))
            )
        case let .grooming(id, messages, context, childAge):
            var ctx = contextPayload(context)
            ctx.childAge = childAge
            return BatchItemPayload(
                id: id, type: "grooming",
                data: BatchItemData(
                    messages: messages.map { ["sender_role": $0.role.rawValue, "text": $0.content] },
                    context: ctx
                )
            )
        case let .text(id, type, text, context):
            return BatchItemPayload(
                id: id, type: type.rawValue,
                data: BatchItemData(text: text, context: contextPayload(context))
            )
        case let .unsafe (id, text, context):
            return BatchItemPayload(
                id: id, type: "unsafe",
                data: BatchItemData(text: text, context: contextPayload(context))
            )
        case let .emotions(id, messages, context):
            return BatchItemPayload(
                id: id, type: "emotions",
                data: BatchItemData(
                    messages: messages.map { ["sender": $0.sender, "text": $0.content] },
                    context: contextPayload(context)
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

    /// Overload for GET/DELETE with no body
    private func request<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil
    ) async throws -> T {
        try await requestRetrying(method: method, path: path, bodyData: nil, query: query)
    }

    /// Overload for pre-encoded body data
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

        for attempt in 0 ..< maxRetries {
            try Task.checkCancellation()

            let data: Data
            do {
                data = try await performRequest(method: method, path: path, bodyData: bodyData, query: query)
            } catch {
                lastError = try retryable(error)
                try await backOff(after: attempt)
                continue
            }

            // Not retried: the request went through, and sending it again would
            // repeat a paid analysis. Cached only once it decodes.
            let value = try decoder.decode(T.self, from: data)
            if let cacheKey = cacheKey {
                setCachedData(data, for: cacheKey, ttl: cacheTTL)
            }
            return value
        }

        throw lastError ?? TuteliqError.unknownError("Request failed after \(maxRetries) attempts")
    }

    /// Returns `error` when another attempt could succeed, and rethrows it when none can.
    private func retryable(_ error: Error) throws -> Error {
        switch error {
        case is CancellationError:
            throw error
        case let error as TuteliqError:
            switch error {
            case .authenticationError, .validationError, .notFoundError, .subscriptionError, .quotaExceededError:
                throw error
            default:
                return error
            }
        default:
            return error
        }
    }

    private func backOff(after attempt: Int) async throws {
        if attempt < maxRetries - 1 {
            let delay = retryDelay * pow(2.0, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
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

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
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
            case 429 where Self.quotaErrorCodes.contains(errorResponse?.error.code ?? ""):
                throw TuteliqError.quotaExceededError(message)
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

        for attempt in 0 ..< maxRetries {
            try Task.checkCancellation()

            let data: Data
            do {
                data = try await performMultipartRequest(path: path, body: body, boundary: boundary)
            } catch {
                lastError = try retryable(error)
                try await backOff(after: attempt)
                continue
            }

            // Not retried: the upload went through, and sending it again would repeat a paid analysis.
            return try decoder.decode(T.self, from: data)
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

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
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
            case 429 where Self.quotaErrorCodes.contains(errorResponse?.error.code ?? ""):
                throw TuteliqError.quotaExceededError(message)
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

    /// An exhausted allowance: `SUB_7004` (message limit reached) and `SUB_7005` (credits
    /// depleted) are what the API sends today.
    private static let quotaErrorCodes: Set<String> = ["SUB_7004", "SUB_7005", "RATE_2003", "QUOTA_EXCEEDED"]

    /// The MIME type the SDK sends for an upload with this filename, or `nil` for an
    /// unrecognised extension.
    ///
    /// The type decides admission (the API rejects `application/octet-stream`)
    /// and behaviour: `image/gif` makes the API analyse an animation frame by frame.
    public static func mimeType(forFilename filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/m4a"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "pdf": return "application/pdf"
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
