import Foundation

// MARK: - Common Types

/// Context for content analysis.
///
/// Provides optional metadata to improve analysis accuracy.
public struct AnalysisContext: Codable, Sendable {
    /// Language code (e.g., `"en"`).
    public var language: String?
    /// Age group range (e.g., `"11-13"`).
    public var ageGroup: String?
    /// Relationship between participants (e.g., `"classmates"`).
    public var relationship: String?
    /// Platform where the content originated (e.g., `"Discord"`).
    public var platform: String?

    public init(
        language: String? = nil,
        ageGroup: String? = nil,
        relationship: String? = nil,
        platform: String? = nil
    ) {
        self.language = language
        self.ageGroup = ageGroup
        self.relationship = relationship
        self.platform = platform
    }

    enum CodingKeys: String, CodingKey {
        case language
        case ageGroup = "age_group"
        case relationship
        case platform
    }
}

/// Monthly usage statistics, populated from response headers.
public struct Usage: Codable, Sendable {
    /// Total monthly API calls available.
    public let limit: Int
    /// API calls used this month.
    public let used: Int
    /// API calls remaining this month.
    public let remaining: Int
    /// Next monthly reset date (YYYY-MM-DD), if available.
    public let reset: String?
    /// Warning message when >80% of monthly limit used, if applicable.
    public let warning: String?
}

/// Rate limit information from response headers.
public struct RateLimitInfo: Sendable {
    /// Maximum requests per minute for your tier.
    public let limit: Int
    /// Remaining requests in current window.
    public let remaining: Int
    /// Unix timestamp (seconds) when rate limit resets.
    public let reset: TimeInterval
}

// MARK: - Bullying Detection

/// Input for bullying detection.
///
/// - Note: The ``content`` field maps to the API `text` field.
public struct DetectBullyingInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Your external correlation ID (max 255 chars).
    public var externalId: String?
    /// Multi-tenant customer ID for webhook routing (max 255 chars).
    public var customerId: String?
    /// Arbitrary key-value metadata echoed back in the response.
    public var metadata: [String: AnyCodable]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from bullying detection.
public struct BullyingResult: Codable, Sendable {
    public let isBullying: Bool
    public let bullyingType: [String]
    public let confidence: Double
    public let severity: Severity
    public let rationale: String
    public let recommendedAction: String
    public let riskScore: Double
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case isBullying = "is_bullying"
        case bullyingType = "bullying_type"
        case confidence, severity, rationale
        case recommendedAction = "recommended_action"
        case riskScore = "risk_score"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Grooming Detection

/// A single message in a grooming detection conversation.
public struct GroomingMessage: Codable, Sendable {
    /// Role of the message sender.
    public var role: MessageRole
    /// Message text content.
    public var content: String
    /// Optional timestamp.
    public var timestamp: Date?

    public init(role: MessageRole, content: String, timestamp: Date? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case role = "sender_role"
        case content = "text"
        case timestamp
    }
}

/// Input for grooming detection.
public struct DetectGroomingInput: Sendable {
    /// Array of conversation messages to analyze.
    public var messages: [GroomingMessage]
    /// Age of the child participant.
    public var childAge: Int?
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        messages: [GroomingMessage],
        childAge: Int? = nil,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from grooming detection.
public struct GroomingResult: Codable, Sendable {
    public let groomingRisk: GroomingRisk
    public let confidence: Double
    public let flags: [String]
    public let rationale: String
    public let riskScore: Double
    public let recommendedAction: String
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case groomingRisk = "grooming_risk"
        case confidence, flags, rationale
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Unsafe Content Detection

/// Input for unsafe content detection.
public struct DetectUnsafeInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from unsafe content detection.
public struct UnsafeResult: Codable, Sendable {
    public let unsafe: Bool
    public let categories: [String]
    public let severity: Severity
    public let confidence: Double
    public let riskScore: Double
    public let rationale: String
    public let recommendedAction: String
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case unsafe, categories, severity, confidence, rationale
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Quick Analysis

/// Input for combined safety analysis.
///
/// Runs bullying and unsafe detection in parallel on the client side.
public struct AnalyzeInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Which analysis types to include (defaults to bullying + unsafe).
    public var include: [AnalysisType]?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        include: [AnalysisType]? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.include = include
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from combined safety analysis.
public struct AnalyzeResult: Codable, Sendable {
    public let riskLevel: String
    public let riskScore: Double
    public let summary: String
    public let bullying: BullyingResult?
    public let unsafe: UnsafeResult?
    public let recommendedAction: String
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    /// Typed risk level (returns `nil` if the server sends an unrecognized value).
    public var riskLevelValue: RiskLevel? { RiskLevel(rawValue: riskLevel) }

    enum CodingKeys: String, CodingKey {
        case riskLevel = "risk_level"
        case riskScore = "risk_score"
        case summary, bullying, unsafe
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Emotion Analysis

/// A single message for emotion analysis.
public struct EmotionMessage: Codable, Sendable {
    /// Sender identifier (e.g., a name or role).
    public var sender: String
    /// Message text content.
    public var content: String
    /// Optional timestamp.
    public var timestamp: Date?

    public init(sender: String, content: String, timestamp: Date? = nil) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case sender
        case content = "text"
        case timestamp
    }
}

/// Input for emotion analysis.
public struct AnalyzeEmotionsInput: Sendable {
    /// Single text content to analyze (wrapped as a message internally).
    public var content: String?
    /// Array of messages to analyze.
    public var messages: [EmotionMessage]?
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        content: String? = nil,
        messages: [EmotionMessage]? = nil,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.messages = messages
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from emotion analysis.
public struct EmotionsResult: Codable, Sendable {
    public let dominantEmotions: [String]
    public let emotionScores: [String: Double]
    public let trend: EmotionTrend
    public let summary: String
    public let recommendedFollowup: String
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case dominantEmotions = "dominant_emotions"
        case emotionScores = "emotion_scores"
        case trend, summary
        case recommendedFollowup = "recommended_followup"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Action Plan

/// Input for generating an action plan.
public struct GetActionPlanInput: Sendable {
    /// Description of the situation.
    public var situation: String
    /// Age of the child involved.
    public var childAge: Int?
    /// Target audience for the plan (defaults to `.parent`).
    public var audience: Audience?
    /// Severity level for context.
    public var severity: Severity?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        situation: String,
        childAge: Int? = nil,
        audience: Audience? = nil,
        severity: Severity? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.situation = situation
        self.childAge = childAge
        self.audience = audience
        self.severity = severity
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from action plan generation.
public struct ActionPlanResult: Codable, Sendable {
    public let audience: String
    public let steps: [String]
    public let tone: String
    public let readingLevel: String?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case audience, steps, tone
        case readingLevel = "approx_reading_level"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Incident Report

/// A single message for incident reports.
public struct ReportMessage: Codable, Sendable {
    /// Sender identifier.
    public var sender: String
    /// Message text content.
    public var content: String
    /// Optional timestamp.
    public var timestamp: Date?

    public init(sender: String, content: String, timestamp: Date? = nil) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case sender
        case content = "text"
        case timestamp
    }
}

/// Input for generating an incident report.
public struct GenerateReportInput: Sendable {
    /// Array of conversation messages.
    public var messages: [ReportMessage]
    /// Age of the child involved.
    public var childAge: Int?
    /// Type of incident (e.g., `"bullying"`, `"grooming"`).
    public var incidentType: String?
    /// Conversation identifier for the meta block.
    public var conversationId: String?
    /// Timestamp range as `[start, end]` ISO strings.
    public var timestampRange: [String]?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?

    public init(
        messages: [ReportMessage],
        childAge: Int? = nil,
        incidentType: String? = nil,
        conversationId: String? = nil,
        timestampRange: [String]? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.incidentType = incidentType
        self.conversationId = conversationId
        self.timestampRange = timestampRange
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Result from incident report generation.
public struct ReportResult: Codable, Sendable {
    public let summary: String
    public let riskLevel: String
    public let categories: [String]
    public let recommendedNextSteps: [String]
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    /// Typed risk level (returns `nil` if the server sends an unrecognized value).
    public var riskLevelValue: RiskLevel? { RiskLevel(rawValue: riskLevel) }

    enum CodingKeys: String, CodingKey {
        case summary, categories
        case riskLevel = "risk_level"
        case recommendedNextSteps = "recommended_next_steps"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - AnyCodable Helper

/// A type-erased `Codable` value for handling dynamic JSON fields.
///
/// Used for `metadata` dictionaries and other unstructured API fields.
/// Supports `Bool`, `Int`, `Double`, `String`, arrays, and dictionaries.
public struct AnyCodable: Codable, @unchecked Sendable {
    /// The underlying value.
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
