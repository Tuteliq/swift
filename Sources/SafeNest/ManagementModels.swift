import Foundation

// MARK: - Policy

/// Result from policy endpoints (`GET /api/v1/policy`, `PUT /api/v1/policy`).
public struct PolicyResult: Codable, Sendable {
    public let success: Bool
    public let config: [String: AnyCodable]
    public let message: String
}

// MARK: - Batch Analysis

/// A single item in a batch analysis request.
///
/// Each case corresponds to an analysis type with its required input data.
/// ```swift
/// let items: [BatchItem] = [
///     .bullying(id: "msg-1", text: "You're not welcome"),
///     .unsafe(id: "msg-2", text: "Some other text"),
///     .grooming(id: "conv-1", messages: groomingMessages),
/// ]
/// ```
public enum BatchItem: Sendable {
    case bullying(id: String, text: String, context: AnalysisContext? = nil)
    case grooming(id: String, messages: [GroomingMessage], context: AnalysisContext? = nil)
    case unsafe(id: String, text: String, context: AnalysisContext? = nil)
    case emotions(id: String, messages: [EmotionMessage], context: AnalysisContext? = nil)
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

    /// Decode the result as a specific type.
    ///
    /// ```swift
    /// if item.type == "bullying" {
    ///     let result = try item.decodeResult(as: BullyingResult.self)
    /// }
    /// ```
    /// - Parameter type: The `Decodable` type to decode the result as.
    /// - Returns: The decoded result, or `nil` if the result is absent.
    public func decodeResult<T: Decodable>(as type: T.Type) throws -> T? {
        guard let result = result else { return nil }
        guard JSONSerialization.isValidJSONObject(result.value) else { return nil }
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

    enum CodingKeys: String, CodingKey {
        case total, successful, failed
        case processingTimeMs = "processing_time_ms"
    }
}

// MARK: - Usage

/// Result from `GET /api/v1/usage/summary`.
public struct UsageSummaryResult: Codable, Sendable {
    public let apiKeyId: String
    public let tier: String
    public let date: String
    public let usage: Stats
    public let quota: Quota

    enum CodingKeys: String, CodingKey {
        case apiKeyId = "api_key_id"
        case tier, date, usage, quota
    }

    public struct Stats: Codable, Sendable {
        public let totalRequests: Int
        public let successRequests: Int
        public let errorRequests: Int

        enum CodingKeys: String, CodingKey {
            case totalRequests = "total_requests"
            case successRequests = "success_requests"
            case errorRequests = "error_requests"
        }
    }

    public struct Quota: Codable, Sendable {
        public let requestsPerMinute: Int
        public let requestsPerMonth: Int
        public let requestsPerDay: Int
        public let remainingToday: Int

        enum CodingKeys: String, CodingKey {
            case requestsPerMinute = "requests_per_minute"
            case requestsPerMonth = "requests_per_month"
            case requestsPerDay = "requests_per_day"
            case remainingToday = "remaining_today"
        }
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

/// Result from `GET /api/v1/usage/quota`.
public struct UsageQuotaResult: Codable, Sendable {
    public let apiKeyId: String
    public let tier: String
    public let limits: Limits
    public let current: Current
    public let remaining: Remaining

    enum CodingKeys: String, CodingKey {
        case apiKeyId = "api_key_id"
        case tier, limits, current, remaining
    }

    public struct Limits: Codable, Sendable {
        public let requestsPerMinute: Int
        public let requestsPerMonth: Int
        public let requestsPerDay: Int

        enum CodingKeys: String, CodingKey {
            case requestsPerMinute = "requests_per_minute"
            case requestsPerMonth = "requests_per_month"
            case requestsPerDay = "requests_per_day"
        }
    }

    public struct Current: Codable, Sendable {
        public let requestsThisMinute: Int
        public let requestsToday: Int

        enum CodingKeys: String, CodingKey {
            case requestsThisMinute = "requests_this_minute"
            case requestsToday = "requests_today"
        }
    }

    public struct Remaining: Codable, Sendable {
        public let requestsThisMinute: Int
        public let requestsToday: Int

        enum CodingKeys: String, CodingKey {
            case requestsThisMinute = "requests_this_minute"
            case requestsToday = "requests_today"
        }
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

    enum CodingKeys: String, CodingKey {
        case name, price, period, description, features
        case isPopular = "is_popular"
        case cta
        case ctaLink = "cta_link"
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
