import Foundation

// MARK: - Common Types

/// Context for content analysis
public struct AnalysisContext: Codable, Sendable {
    public var language: String?
    public var ageGroup: String?
    public var relationship: String?
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

/// Tracking fields for correlating requests
public struct TrackingFields: Codable, Sendable {
    public var externalId: String?
    public var metadata: [String: AnyCodable]?

    public init(externalId: String? = nil, metadata: [String: Any]? = nil) {
        self.externalId = externalId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }

    enum CodingKeys: String, CodingKey {
        case externalId = "external_id"
        case metadata
    }
}

/// Usage statistics
public struct Usage: Codable, Sendable {
    public let limit: Int
    public let used: Int
    public let remaining: Int
}

// MARK: - Bullying Detection

public struct DetectBullyingInput: Sendable {
    public var content: String
    public var context: AnalysisContext?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct BullyingResult: Codable, Sendable {
    public let isBullying: Bool
    public let bullyingType: [String]
    public let confidence: Double
    public let severity: Severity
    public let rationale: String
    public let recommendedAction: String
    public let riskScore: Double
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case isBullying = "is_bullying"
        case bullyingType = "bullying_type"
        case confidence
        case severity
        case rationale
        case recommendedAction = "recommended_action"
        case riskScore = "risk_score"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Grooming Detection

public struct GroomingMessage: Codable, Sendable {
    public var role: MessageRole
    public var content: String
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

public struct DetectGroomingInput: Sendable {
    public var messages: [GroomingMessage]
    public var childAge: Int?
    public var context: AnalysisContext?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        messages: [GroomingMessage],
        childAge: Int? = nil,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.context = context
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct GroomingResult: Codable, Sendable {
    public let groomingRisk: GroomingRisk
    public let confidence: Double
    public let flags: [String]
    public let rationale: String
    public let riskScore: Double
    public let recommendedAction: String
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case groomingRisk = "grooming_risk"
        case confidence
        case flags
        case rationale
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Unsafe Content Detection

public struct DetectUnsafeInput: Sendable {
    public var content: String
    public var context: AnalysisContext?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct UnsafeResult: Codable, Sendable {
    public let unsafe: Bool
    public let categories: [String]
    public let severity: Severity
    public let confidence: Double
    public let riskScore: Double
    public let rationale: String
    public let recommendedAction: String
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case unsafe
        case categories
        case severity
        case confidence
        case riskScore = "risk_score"
        case rationale
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Quick Analysis

public struct AnalyzeInput: Sendable {
    public var content: String
    public var context: AnalysisContext?
    public var include: [AnalysisType]?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        include: [AnalysisType]? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.context = context
        self.include = include
        self.externalId = externalId
        self.metadata = metadata
    }
}

public enum AnalysisType: String, Codable, Sendable {
    case bullying
    case unsafe
    case grooming
}

public struct AnalyzeResult: Codable, Sendable {
    public let riskLevel: RiskLevel
    public let riskScore: Double
    public let summary: String
    public let bullying: BullyingResult?
    public let unsafe: UnsafeResult?
    public let recommendedAction: String
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case riskLevel = "risk_level"
        case riskScore = "risk_score"
        case summary
        case bullying
        case unsafe
        case recommendedAction = "recommended_action"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Emotion Analysis

public struct EmotionMessage: Codable, Sendable {
    public var sender: String
    public var content: String
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

public struct AnalyzeEmotionsInput: Sendable {
    public var content: String?
    public var messages: [EmotionMessage]?
    public var context: AnalysisContext?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        content: String? = nil,
        messages: [EmotionMessage]? = nil,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.messages = messages
        self.context = context
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct EmotionsResult: Codable, Sendable {
    public let dominantEmotions: [String]
    public let emotionScores: [String: Double]
    public let trend: EmotionTrend
    public let summary: String
    public let recommendedFollowup: String
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case dominantEmotions = "dominant_emotions"
        case emotionScores = "emotion_scores"
        case trend
        case summary
        case recommendedFollowup = "recommended_followup"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Action Plan

public struct GetActionPlanInput: Sendable {
    public var situation: String
    public var childAge: Int?
    public var audience: Audience?
    public var severity: Severity?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        situation: String,
        childAge: Int? = nil,
        audience: Audience? = nil,
        severity: Severity? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.situation = situation
        self.childAge = childAge
        self.audience = audience
        self.severity = severity
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct ActionPlanResult: Codable, Sendable {
    public let audience: String
    public let steps: [String]
    public let tone: String
    public let readingLevel: String?
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case audience
        case steps
        case tone
        case readingLevel = "approx_reading_level"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - Incident Report

public struct ReportMessage: Codable, Sendable {
    public var sender: String
    public var content: String
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

public struct GenerateReportInput: Sendable {
    public var messages: [ReportMessage]
    public var childAge: Int?
    public var incidentType: String?
    public var occurredAt: Date?
    public var notes: String?
    public var externalId: String?
    public var metadata: [String: Any]?

    public init(
        messages: [ReportMessage],
        childAge: Int? = nil,
        incidentType: String? = nil,
        occurredAt: Date? = nil,
        notes: String? = nil,
        externalId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.incidentType = incidentType
        self.occurredAt = occurredAt
        self.notes = notes
        self.externalId = externalId
        self.metadata = metadata
    }
}

public struct ReportResult: Codable, Sendable {
    public let summary: String
    public let riskLevel: RiskLevel
    public let categories: [String]
    public let recommendedNextSteps: [String]
    public let externalId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case summary
        case riskLevel = "risk_level"
        case categories
        case recommendedNextSteps = "recommended_next_steps"
        case externalId = "external_id"
        case metadata
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, Sendable {
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
