import Foundation

// MARK: - Policy

/// Result from policy endpoints (`GET /api/v1/policy`, `PUT /api/v1/policy`).
///
/// `config` uses the API's camelCase keys (`bullying.minRiskScoreToFlag`, `selfHarm`, …).
public struct PolicyResult: Codable, Sendable {
    public let success: Bool
    public let config: [String: AnyCodable]?
    public let message: String?
}

// MARK: - Batch Analysis

/// Text-based analysis types accepted by batch analysis.
public enum BatchTextType: String, Codable, Sendable {
    case bullying
    case unsafe
    case socialEngineering = "social_engineering"
    case appFraud = "app_fraud"
    case romanceScam = "romance_scam"
    case muleRecruitment = "mule_recruitment"
    case gamblingHarm = "gambling_harm"
    case coerciveControl = "coercive_control"
    case vulnerabilityExploitation = "vulnerability_exploitation"
    case radicalisation
}

/// A single item in a batch analysis request.
///
/// `id` addresses the item within this request and is echoed on its result.
/// It is not `externalId`, which is your own record's identifier.
/// ```swift
/// let items: [BatchItem] = [
///     .bullying(id: "msg-1", text: "You're not welcome"),
///     .text(id: "msg-2", type: .romanceScam, text: "Send me the gift card codes"),
///     .grooming(id: "conv-1", messages: groomingMessages, childAge: 12),
/// ]
/// ```
public enum BatchItem: Sendable {
    case bullying(id: String, text: String, context: AnalysisContext? = nil)
    case grooming(id: String, messages: [GroomingMessage], context: AnalysisContext? = nil, childAge: Int? = nil)
    case unsafe (id: String, text: String, context: AnalysisContext? = nil)
    case emotions(id: String, messages: [EmotionMessage], context: AnalysisContext? = nil)
    /// Any text-based type, including the fraud and safety-extended detectors.
    case text(id: String, type: BatchTextType, text: String, context: AnalysisContext? = nil)

    var id: String {
        switch self {
        case let .bullying(id, _, _), let .grooming(id, _, _, _), let .unsafe (id, _, _),
             let .emotions(id, _, _), let .text(id, _, _, _):
            return id
        }
    }
}

/// Input for batch analysis.
///
/// Supports up to 50 items per request.
public struct BatchAnalyzeInput: Sendable {
    /// Items to analyze (max 50).
    public var items: [BatchItem]
    /// Whether to process items in parallel on the server (default: true).
    public var parallel: Bool

    public init(items: [BatchItem], parallel: Bool = true) {
        self.items = items
        self.parallel = parallel
    }
}

/// Result from batch analysis.
public struct BatchAnalyzeResult: Codable, Sendable {
    public let results: [BatchResultItem]
    public let summary: BatchSummary
}

/// A single result item from a batch analysis.
public struct BatchResultItem: Codable, Sendable {
    /// Your item ID, echoed back.
    public let id: String
    /// Analysis type that was performed.
    public let type: String
    /// Whether analysis succeeded.
    public let success: Bool
    /// The analysis result (type varies by analysis type). Use ``decodeResult(as:)`` for typed access.
    public let result: AnyCodable?
    /// Error message if analysis failed.
    public let error: String?
    /// Credits consumed by this item.
    public let creditsUsed: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, success, result, error
        case creditsUsed = "credits_used"
    }

    /// Decode the result as a specific type.
    ///
    /// ```swift
    /// if item.type == "bullying" {
    ///     let result = try item.decodeResult(as: BullyingResult.self)
    /// }
    /// ```
    /// - Parameter type: The `Decodable` type to decode the result as.
    /// - Returns: The decoded result, or `nil` if the result is absent.
    public func decodeResult<T: Decodable>(as _: T.Type) throws -> T? {
        guard let result = result, JSONSerialization.isValidJSONObject(result.value) else { return nil }
        let data = try JSONSerialization.data(withJSONObject: result.value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

/// Summary statistics from a batch analysis.
public struct BatchSummary: Codable, Sendable {
    public let total: Int
    public let successful: Int
    public let failed: Int
    public let processingTimeMs: Int
    /// Total credits consumed across all items.
    public let totalCreditsUsed: Int?

    /// The API sends `processingTimeMs` in camelCase alongside snake_case `total_credits_used`.
    enum CodingKeys: String, CodingKey {
        case total, successful, failed
        case processingTimeMs
        case totalCreditsUsed = "total_credits_used"
    }
}

// MARK: - Usage

/// Result from `GET /api/v1/usage/summary`. The API sends this shape in camelCase.
public struct UsageSummaryResult: Codable, Sendable {
    public let apiKeyId: String
    public let tier: String
    public let date: String
    public let usage: Stats
    public let quota: Quota

    public struct Stats: Codable, Sendable {
        public let totalRequests: Int
        public let successRequests: Int
        public let errorRequests: Int
    }

    public struct Quota: Codable, Sendable {
        public let requestsPerMinute: Int
        /// The tier's monthly allowance: the limit that matters on a paid
        /// tier, whose `requestsPerDay` is `-1`. `-1` means unlimited.
        public let requestsPerMonth: Int
        /// `-1` means unlimited.
        public let requestsPerDay: Int
        /// `-1` means unlimited.
        public let remainingToday: Int
    }
}

/// Result from `GET /api/v1/usage/history`.
public struct UsageHistoryResult: Codable, Sendable {
    public let apiKeyId: String
    public let days: [Day]

    enum CodingKeys: String, CodingKey {
        case apiKeyId = "api_key_id"
        case days
    }

    public struct Day: Codable, Sendable {
        public let date: String
        public let totalRequests: Int
        public let successRequests: Int
        public let errorRequests: Int

        enum CodingKeys: String, CodingKey {
            case date
            case totalRequests = "total_requests"
            case successRequests = "success_requests"
            case errorRequests = "error_requests"
        }
    }
}

/// Result from `GET /api/v1/usage/quota`. The API sends this shape in camelCase.
public struct UsageQuotaResult: Codable, Sendable {
    public let apiKeyId: String?
    public let tier: String
    public let limits: Limits
    public let current: Current
    public let remaining: Remaining
    /// Seconds until the per-minute window resets. `nil` on API deployments before 2026-09-21.
    public let resetsInSeconds: Int?

    public struct Limits: Codable, Sendable {
        public let requestsPerMinute: Int
        /// The tier's monthly allowance: the limit that matters on a paid
        /// tier, whose `requestsPerDay` is `-1`. `-1` means unlimited.
        public let requestsPerMonth: Int
        /// `-1` means unlimited.
        public let requestsPerDay: Int
    }

    public struct Current: Codable, Sendable {
        public let requestsThisMinute: Int
        public let requestsToday: Int
    }

    public struct Remaining: Codable, Sendable {
        public let requestsThisMinute: Int
        /// `-1` means unlimited.
        public let requestsToday: Int
    }
}

/// Result from `GET /api/v1/usage/by-tool`.
public struct UsageByToolResult: Codable, Sendable {
    public let date: String
    public let tools: [String: Int]
    public let endpoints: [String: Int]
}

/// Result from `GET /api/v1/usage/monthly`.
public struct UsageMonthlyResult: Codable, Sendable {
    public let tier: String
    public let tierDisplayName: String
    public let billing: Billing
    public let usage: MonthlyUsage
    public let rateLimit: RateLimit
    public let recommendations: Recommendation?
    public let links: Links

    enum CodingKeys: String, CodingKey {
        case tier
        case tierDisplayName = "tier_display_name"
        case billing, usage
        case rateLimit = "rate_limit"
        case recommendations, links
    }

    public struct Billing: Codable, Sendable {
        public let currentPeriodStart: String
        public let currentPeriodEnd: String
        public let daysRemaining: Int

        enum CodingKeys: String, CodingKey {
            case currentPeriodStart = "current_period_start"
            case currentPeriodEnd = "current_period_end"
            case daysRemaining = "days_remaining"
        }
    }

    public struct MonthlyUsage: Codable, Sendable {
        public let used: Int
        public let limit: Int
        public let remaining: Int
        public let percentUsed: Double

        enum CodingKeys: String, CodingKey {
            case used, limit, remaining
            case percentUsed = "percent_used"
        }
    }

    public struct RateLimit: Codable, Sendable {
        public let requestsPerMinute: Int

        enum CodingKeys: String, CodingKey {
            case requestsPerMinute = "requests_per_minute"
        }
    }

    public struct Recommendation: Codable, Sendable {
        public let shouldUpgrade: Bool
        public let reason: String
        public let suggestedTier: String
        public let upgradeUrl: String

        enum CodingKeys: String, CodingKey {
            case shouldUpgrade = "should_upgrade"
            case reason
            case suggestedTier = "suggested_tier"
            case upgradeUrl = "upgrade_url"
        }
    }

    public struct Links: Codable, Sendable {
        public let dashboard: String
        public let pricing: String
        public let buyCredits: String

        enum CodingKeys: String, CodingKey {
            case dashboard, pricing
            case buyCredits = "buy_credits"
        }
    }
}

// MARK: - Webhooks

/// A webhook configuration.
public struct Webhook: Codable, Sendable {
    public let id: String
    public let name: String
    public let url: String
    public let events: [String]
    public let isActive: Bool
    public let failureCount: Int
    public let lastTriggeredAt: String?
    public let lastError: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, url, events
        case isActive = "is_active"
        case failureCount = "failure_count"
        case lastTriggeredAt = "last_triggered_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Result from `GET /api/v1/webhooks`.
public struct WebhookListResult: Codable, Sendable {
    public let webhooks: [Webhook]
}

/// Input for creating a webhook.
public struct CreateWebhookInput: Sendable {
    /// Webhook name (max 100 chars).
    public var name: String
    /// Webhook URL (must be HTTPS).
    public var url: String
    /// Event types to subscribe to (1-5 events).
    public var events: [WebhookEventType]
    /// Optional custom headers to send with webhook payloads.
    public var headers: [String: String]?

    public init(
        name: String,
        url: String,
        events: [WebhookEventType],
        headers: [String: String]? = nil
    ) {
        self.name = name
        self.url = url
        self.events = events
        self.headers = headers
    }
}

/// Result from `POST /api/v1/webhooks`.
public struct CreateWebhookResult: Codable, Sendable {
    public let id: String
    public let name: String
    public let url: String
    /// Webhook signing secret. Only returned on creation.
    public let secret: String
    public let events: [String]
    public let isActive: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, url, secret, events
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

/// Input for updating a webhook.
public struct UpdateWebhookInput: Sendable {
    public var name: String?
    public var url: String?
    public var events: [WebhookEventType]?
    public var isActive: Bool?
    public var headers: [String: String]?

    public init(
        name: String? = nil,
        url: String? = nil,
        events: [WebhookEventType]? = nil,
        isActive: Bool? = nil,
        headers: [String: String]? = nil
    ) {
        self.name = name
        self.url = url
        self.events = events
        self.isActive = isActive
        self.headers = headers
    }
}

/// Result from `PUT /api/v1/webhooks/:id`.
public struct UpdateWebhookResult: Codable, Sendable {
    public let id: String
    public let name: String
    public let url: String
    public let events: [String]
    public let isActive: Bool
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, url, events
        case isActive = "is_active"
        case updatedAt = "updated_at"
    }
}

/// Result from `DELETE /api/v1/webhooks/:id`.
public struct DeleteResult: Codable, Sendable {
    public let success: Bool
    public let message: String
}

/// Result from `POST /api/v1/webhooks/test`.
public struct TestWebhookResult: Codable, Sendable {
    public let success: Bool
    public let statusCode: Int
    public let latencyMs: Int
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case statusCode = "status_code"
        case latencyMs = "latency_ms"
        case error
    }
}

/// Result from `POST /api/v1/webhooks/:id/regenerate-secret`.
public struct RegenerateSecretResult: Codable, Sendable {
    public let secret: String
}

// MARK: - Pricing

/// A public pricing plan.
public struct PricingPlan: Codable, Sendable {
    public let name: String
    public let price: String
    public let period: String
    public let description: String
    public let features: [String]
    public let isPopular: Bool
    public let cta: String
    public let ctaLink: String

    /// `/pricing` sends these in camelCase, unlike `/pricing/details`.
    enum CodingKeys: String, CodingKey {
        case name, price, period, description, features, isPopular, cta, ctaLink
    }
}

/// Result from `GET /api/v1/pricing`.
public struct PricingResult: Codable, Sendable {
    public let plans: [PricingPlan]
}

/// A detailed pricing plan (requires authentication).
public struct PricingDetailPlan: Codable, Sendable {
    public let id: String
    public let name: String
    public let tier: String
    public let description: String
    public let priceMonthly: Double
    public let priceYearly: Double
    public let apiCallsPerMonth: Int
    public let rateLimit: Int
    public let features: [String]
    public let isPopular: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, tier, description, features
        case priceMonthly = "price_monthly"
        case priceYearly = "price_yearly"
        case apiCallsPerMonth = "api_calls_per_month"
        case rateLimit = "rate_limit"
        case isPopular = "is_popular"
    }
}

/// Result from `GET /api/v1/pricing/details`.
public struct PricingDetailsResult: Codable, Sendable {
    public let plans: [PricingDetailPlan]
}

// MARK: - Account Management (GDPR)

/// Result from `DELETE /api/v1/account/data` (GDPR Article 17 — Right to Erasure).
public struct AccountDeletionResult: Codable, Sendable {
    public let message: String
    public let deletedCount: Int

    private enum CodingKeys: String, CodingKey {
        case message
        case deletedCount = "deleted_count"
    }
}

/// Result from `GET /api/v1/account/export` (GDPR Article 20 — Right to Data Portability).
public struct AccountExportResult: Codable, Sendable {
    public let userId: String
    public let exportedAt: String
    public let data: [String: [AnyCodable]]

    private enum CodingKeys: String, CodingKey {
        case userId
        case exportedAt
        case data
    }
}

// MARK: - Consent Management (GDPR Article 7)

/// Types of consent.
public enum ConsentType: String, Codable, Sendable {
    case dataProcessing = "data_processing"
    case analytics
    case marketing
    case thirdPartySharing = "third_party_sharing"
    case childSafetyMonitoring = "child_safety_monitoring"
}

/// Consent status values.
public enum ConsentStatus: String, Codable, Sendable {
    case granted
    case withdrawn
}

/// Input for recording consent.
public struct RecordConsentInput: Sendable {
    public var consentType: ConsentType
    public var version: String

    public init(consentType: ConsentType, version: String) {
        self.consentType = consentType
        self.version = version
    }
}

/// A consent record.
public struct ConsentRecord: Codable, Sendable {
    public let id: String
    public let userId: String
    public let consentType: String
    public let status: String
    public let version: String
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case consentType = "consent_type"
        case status
        case version
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try decodeUserId(from: decoder)
        consentType = try container.decode(String.self, forKey: .consentType)
        status = try container.decode(String.self, forKey: .status)
        version = try container.decode(String.self, forKey: .version)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

/// Result from consent record/withdraw operations.
public struct ConsentActionResult: Codable, Sendable {
    public let message: String
    public let consent: ConsentRecord
}

/// Result from consent status query.
public struct ConsentStatusResult: Codable, Sendable {
    public let consents: [ConsentRecord]
}

// MARK: - Right to Rectification (GDPR Article 16)

/// Input for data rectification.
public struct RectifyDataInput: Sendable {
    public var collection: String
    public var documentId: String
    public var fields: [String: AnyCodable]

    public init(collection: String, documentId: String, fields: [String: AnyCodable]) {
        self.collection = collection
        self.documentId = documentId
        self.fields = fields
    }
}

/// Result from data rectification.
public struct RectifyDataResult: Codable, Sendable {
    public let message: String
    public let updatedFields: [String]

    private enum CodingKeys: String, CodingKey {
        case message
        case updatedFields = "updated_fields"
    }
}

// MARK: - Audit Logs (GDPR Article 15)

/// Types of auditable actions.
public enum AuditAction: String, Codable, Sendable {
    case dataAccess = "data_access"
    case dataExport = "data_export"
    case dataDeletion = "data_deletion"
    case dataRectification = "data_rectification"
    case consentGranted = "consent_granted"
    case consentWithdrawn = "consent_withdrawn"
    case breachNotification = "breach_notification"
}

/// An audit log entry.
public struct AuditLogEntry: Codable, Sendable {
    public let id: String
    public let userId: String
    public let action: String
    public let details: AnyCodable?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case action
        case details
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try decodeUserId(from: decoder)
        action = try container.decode(String.self, forKey: .action)
        details = try container.decodeIfPresent(AnyCodable.self, forKey: .details)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

/// Consent and audit records carry the user as camelCase `userId` while every
/// other key is snake_case. `user_id` is accepted too, should that ever be aligned.
private func decodeUserId(from decoder: Decoder) throws -> String {
    struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }
    let container = try decoder.container(keyedBy: Key.self)
    if let userId = try container.decodeIfPresent(String.self, forKey: Key(stringValue: "userId")) {
        return userId
    }
    return try container.decode(String.self, forKey: Key(stringValue: "user_id"))
}

/// Result from audit logs query.
public struct AuditLogsResult: Codable, Sendable {
    public let auditLogs: [AuditLogEntry]

    private enum CodingKeys: String, CodingKey {
        case auditLogs = "audit_logs"
    }
}
