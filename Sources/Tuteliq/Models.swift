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
    /// Your app or product name (e.g. `"MyApp"`), used for dashboard attribution.
    ///
    /// The SDK appends its own identifier before sending it: `"MyApp"` reaches
    /// the API as `"MyApp - Swift SDK"`. Pass your product's name here, not a
    /// category like `"chat"`.
    public var platform: String?
    /// ISO 3166-1 alpha-2 country code (e.g. `"GB"`, `"US"`) for geo-localised helpline data.
    public var country: String?
    /// Prior turns of this conversation, oldest first, for THIS request only.
    ///
    /// Never stored server-side. Lets a single call see the trajectory a
    /// gradually-building risk needs. Supported by `detectUnsafe` and the
    /// fraud / coercive-control / distress-signals family; ignored by endpoints
    /// with their own multi-turn input (use `continuationToken` on
    /// `detectBullying`, or `messages` on `detectGrooming`).
    public var priorMessages: [PriorMessage]?

    public init(
        language: String? = nil,
        ageGroup: String? = nil,
        relationship: String? = nil,
        platform: String? = nil,
        country: String? = nil,
        priorMessages: [PriorMessage]? = nil
    ) {
        self.language = language
        self.ageGroup = ageGroup
        self.relationship = relationship
        self.platform = platform
        self.country = country
        self.priorMessages = priorMessages
    }

    enum CodingKeys: String, CodingKey {
        case language
        case ageGroup = "age_group"
        case relationship
        case platform
        case country
        case priorMessages = "prior_messages"
    }
}

/// One prior turn of a conversation, for ``AnalysisContext/priorMessages``.
public struct PriorMessage: Codable, Sendable {
    /// Sender's role in this conversation (e.g. `"user"`, `"contact"`, `"adult"`, `"child"`).
    public var role: String
    /// Message text.
    public var text: String
    /// ISO 8601 timestamp of the message.
    public var timestamp: String?

    public init(role: String, text: String, timestamp: String? = nil) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - Crisis Support

/// A single crisis helpline entry.
public struct SupportHelpline: Codable, Sendable {
    public let name: String
    /// Phone number or short code, as dialled locally.
    public let number: String
    public let description: String?
    /// Coarse topic, e.g. `childProtection`, `mentalHealth`, `domesticViolence`, `general`.
    public let category: String?
    /// Opening hours, e.g. `"24/7"`.
    public let available: String?
}

/// A resource linked from a ``SupportResponseGuide``.
public struct SupportResource: Codable, Sendable {
    public let name: String
    public let description: String?
    public let url: String?
}

/// Guidance shown alongside the helplines.
public struct SupportResponseGuide: Codable, Sendable {
    public let category: String?
    public let immediateActions: [String]
    public let childSpecificActions: [String]?
    public let resources: [SupportResource]
    public let confidential: Bool?
    public let language: String?
}

/// Crisis support attached to a positive detection that meets the request's `supportThreshold`.
///
/// Localised to `context.country` when supplied, otherwise to the account's
/// country, otherwise inferred from the detected language.
public struct SupportData: Codable, Sendable {
    public let country: String?
    public let countryName: String?
    public let emergencyNumber: String?
    public let helplines: [SupportHelpline]
    /// Highest-priority guide.
    public let responseGuide: SupportResponseGuide?
    /// All matching guides, highest priority first.
    public let responseGuides: [SupportResponseGuide]?
    public let language: String?

    enum CodingKeys: String, CodingKey {
        case country
        case countryName = "country_name"
        case emergencyNumber = "emergency_number"
        case helplines
        case responseGuide = "response_guide"
        case responseGuides = "response_guides"
        case language
    }
}

// MARK: - Additive Word-List Flags

/// Deterministic profanity word-list result. Additive: never affects risk scoring or `recommendedAction`.
public struct ProfanityResult: Codable, Sendable {
    public let detected: Bool
    public let matches: [String]
}

/// A single drug/violence term match.
public struct RiskTermMatch: Codable, Sendable {
    public let term: String
    /// `"drug"` or `"violence"`.
    public let category: String
}

/// Deterministic drug/violence word-list result. Purely lexical: can fire on benign
/// uses of a term ("kill the lights"). Never affects risk scoring or `recommendedAction`.
public struct RiskTermsResult: Codable, Sendable {
    public let detected: Bool
    public let matches: [RiskTermMatch]
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
    /// Minimum severity to include crisis support resources (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Fast mode: skips `actionDetail` for lower latency. `rationale` and the verdict are unchanged.
    public var verdictOnly: Bool
    /// Token from a prior `/bullying` result. Carries derived trajectory state
    /// (no content) into this call so risk is tracked across turns.
    public var continuationToken: String?
    /// Discard any `continuationToken` and start a fresh conversation.
    public var resetConversation: Bool
    /// Adds a deterministic `profanity` word-list result. Free and additive.
    /// `true`/`false` overrides the account default; `nil` uses it.
    public var flagProfanity: Bool?
    /// Adds a deterministic drug/violence `riskTerms` word-list result. Free and additive.
    /// `true`/`false` overrides the account default; `nil` uses it.
    public var flagRiskTerms: Bool?
    /// Per-call override of the account's incident logging. `false` suppresses
    /// persistence (e.g. test traffic); `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        supportThreshold: SupportThreshold? = nil,
        verdictOnly: Bool = false,
        continuationToken: String? = nil,
        resetConversation: Bool = false,
        flagProfanity: Bool? = nil,
        flagRiskTerms: Bool? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.supportThreshold = supportThreshold
        self.verdictOnly = verdictOnly
        self.continuationToken = continuationToken
        self.resetConversation = resetConversation
        self.flagProfanity = flagProfanity
        self.flagRiskTerms = flagRiskTerms
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from bullying detection.
///
/// Branch on ``recommendedAction`` (or its `isActionable`), not on ``isBullying``,
/// which fires on monitor-only signals too. For multi-turn work, branch on the
/// higher of ``riskScore`` and ``trajectoryRisk``.
public struct BullyingResult: Codable, Sendable {
    public let isBullying: Bool
    public let bullyingType: [String]
    public let confidence: Double
    public let severity: Severity
    /// What a moderator reads to triage the incident. Always generated, including in fast mode.
    public let rationale: String?
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction` for a moderator UI. Do not branch on it.
    /// Omitted in fast mode (`verdictOnly`).
    public let actionDetail: String?
    /// Risk of this message alone (0–1).
    public let riskScore: Double
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?
    /// Pass back as `continuationToken` on the next call to keep multi-turn awareness.
    public let continuationToken: String?
    /// ISO 8601 expiry of `continuationToken`.
    public let continuationExpiresAt: String?
    public let stateSource: StateSource?
    /// Conversation-level risk (0–1). Absent on the first turn of a fresh conversation.
    public let trajectoryRisk: Double?
    public let trajectory: ConversationTrajectory?
    /// Per-turn severity, oldest first: the evidence behind `trajectoryRisk`.
    public let severitySeries: [Double]?
    /// True when a coded-term corroboration cap held `recommendedAction` below `immediateIntervention`.
    public let escalationCapped: Bool?
    public let escalationCappedReason: String?
    /// Present when `flagProfanity` (or the account default) is on.
    public let profanity: ProfanityResult?
    /// Present when `flagRiskTerms` (or the account default) is on.
    public let riskTerms: RiskTermsResult?
    /// Crisis support, present when the result meets `supportThreshold`.
    public let support: SupportData?

    enum CodingKeys: String, CodingKey {
        case isBullying = "is_bullying"
        case bullyingType = "bullying_type"
        case confidence, severity, rationale
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case riskScore = "risk_score"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
        case continuationToken = "continuation_token"
        case continuationExpiresAt = "continuation_expires_at"
        case stateSource = "state_source"
        case trajectoryRisk = "trajectory_risk"
        case trajectory
        case severitySeries = "severity_series"
        case escalationCapped = "escalation_capped"
        case escalationCappedReason = "escalation_capped_reason"
        case profanity
        case riskTerms = "risk_terms"
        case support
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
    /// Age of THIS message's sender, so age asymmetry is reasoned per turn rather than inferred from `role`.
    public var senderAge: Int?

    public init(role: MessageRole, content: String, timestamp: Date? = nil, senderAge: Int? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.senderAge = senderAge
    }

    enum CodingKeys: String, CodingKey {
        case role = "sender_role"
        case content = "text"
        case timestamp
        case senderAge = "sender_age"
    }
}

/// Input for grooming detection.
public struct DetectGroomingInput: Sendable {
    /// Array of conversation messages to analyze (max 100).
    public var messages: [GroomingMessage]
    /// Age of the child participant.
    public var childAge: Int?
    /// Age of the non-minor participant, when known (e.g. on age-verified platforms).
    public var participantAge: Int?
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?
    /// Minimum severity to include crisis support resources (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Fast mode: omits `messageAnalysis`. The verdict is unchanged.
    public var verdictOnly: Bool
    /// Token from a prior `/grooming` result, for conversations longer than one window (~20–30 turns).
    public var continuationToken: String?
    /// Discard any `continuationToken` and analyze as a fresh conversation.
    public var resetConversation: Bool
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        messages: [GroomingMessage],
        childAge: Int? = nil,
        participantAge: Int? = nil,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        supportThreshold: SupportThreshold? = nil,
        verdictOnly: Bool = false,
        continuationToken: String? = nil,
        resetConversation: Bool = false,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.participantAge = participantAge
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.supportThreshold = supportThreshold
        self.verdictOnly = verdictOnly
        self.continuationToken = continuationToken
        self.resetConversation = resetConversation
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from grooming detection.
///
/// `groomingRisk == .low` is monitor-only. Branch on ``recommendedAction``
/// (or its `isActionable`), and on the higher of ``riskScore`` and ``trajectoryRisk``.
public struct GroomingResult: Codable, Sendable {
    public let groomingRisk: GroomingRisk
    public let confidence: Double
    public let flags: [String]
    public let rationale: String
    public let riskScore: Double
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it. Omitted in fast mode.
    public let actionDetail: String?
    /// Omitted in fast mode (`verdictOnly`).
    public let messageAnalysis: [MessageAnalysis]?
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?
    public let continuationToken: String?
    public let continuationExpiresAt: String?
    public let stateSource: StateSource?
    /// Conversation-level risk (0–1) across every window so far. Absent on the first call.
    public let trajectoryRisk: Double?
    public let trajectory: ConversationTrajectory?
    /// Per-window severity, oldest first.
    public let severitySeries: [Double]?
    public let support: SupportData?

    enum CodingKeys: String, CodingKey {
        case groomingRisk = "grooming_risk"
        case confidence, flags, rationale
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case messageAnalysis = "message_analysis"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
        case continuationToken = "continuation_token"
        case continuationExpiresAt = "continuation_expires_at"
        case stateSource = "state_source"
        case trajectoryRisk = "trajectory_risk"
        case trajectory
        case severitySeries = "severity_series"
        case support
    }
}

// MARK: - Unsafe Content Detection

/// Input for unsafe content detection.
public struct DetectUnsafeInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Optional analysis context. Use `priorMessages` to submit earlier turns for this call.
    public var context: AnalysisContext?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?
    /// Minimum severity to include crisis support resources (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Fast mode: skips `actionDetail`. `rationale` and the verdict are unchanged.
    public var verdictOnly: Bool
    /// Token from a prior `/unsafe` result: the alternative to resending the
    /// whole conversation in `context.priorMessages` on every call.
    public var continuationToken: String?
    /// Discard any `continuationToken` and start a fresh conversation.
    public var resetConversation: Bool
    /// Adds a deterministic `profanity` word-list result; `nil` uses the account default.
    public var flagProfanity: Bool?
    /// Adds a deterministic drug/violence `riskTerms` result; `nil` uses the account default.
    public var flagRiskTerms: Bool?
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        supportThreshold: SupportThreshold? = nil,
        verdictOnly: Bool = false,
        continuationToken: String? = nil,
        resetConversation: Bool = false,
        flagProfanity: Bool? = nil,
        flagRiskTerms: Bool? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.context = context
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.supportThreshold = supportThreshold
        self.verdictOnly = verdictOnly
        self.continuationToken = continuationToken
        self.resetConversation = resetConversation
        self.flagProfanity = flagProfanity
        self.flagRiskTerms = flagRiskTerms
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from unsafe content detection.
///
/// Branch on ``recommendedAction`` (or its `isActionable`), not on ``unsafe``,
/// which also fires on monitor-only venting ("today was the worst").
public struct UnsafeResult: Codable, Sendable {
    public let unsafe: Bool
    public let categories: [String]
    public let severity: Severity
    public let confidence: Double
    public let riskScore: Double
    /// `none` / `low` / `medium` / `high` / `critical`, derived from `riskScore`.
    public let riskLevel: String?
    /// Always generated, including in fast mode.
    public let rationale: String?
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it. Omitted in fast mode.
    public let actionDetail: String?
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?
    public let continuationToken: String?
    public let continuationExpiresAt: String?
    public let stateSource: StateSource?
    /// Conversation-level risk (0–1). Absent on the first turn.
    public let trajectoryRisk: Double?
    public let trajectory: ConversationTrajectory?
    public let severitySeries: [Double]?
    public let escalationCapped: Bool?
    public let escalationCappedReason: String?
    public let profanity: ProfanityResult?
    public let riskTerms: RiskTermsResult?
    public let support: SupportData?

    enum CodingKeys: String, CodingKey {
        case unsafe, categories, severity, confidence, rationale
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
        case continuationToken = "continuation_token"
        case continuationExpiresAt = "continuation_expires_at"
        case stateSource = "state_source"
        case trajectoryRisk = "trajectory_risk"
        case trajectory
        case severitySeries = "severity_series"
        case escalationCapped = "escalation_capped"
        case escalationCappedReason = "escalation_capped_reason"
        case profanity
        case riskTerms = "risk_terms"
        case support
    }
}

// MARK: - Quick Analysis

/// Input for combined safety analysis.
///
/// Runs bullying and unsafe detection in parallel on the client side.
/// It takes no continuation token, so every call is a fresh first turn; for
/// multi-turn work call ``Tuteliq/detectBullying(_:)`` or ``Tuteliq/detectUnsafe(_:)`` directly.
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
    /// Fast mode, forwarded to both detectors.
    public var verdictOnly: Bool
    /// Forwarded to both detectors; `nil` uses the account default.
    public var flagProfanity: Bool?
    /// Forwarded to both detectors; `nil` uses the account default.
    public var flagRiskTerms: Bool?
    /// Forwarded to both detectors; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        include: [AnalysisType]? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        verdictOnly: Bool = false,
        flagProfanity: Bool? = nil,
        flagRiskTerms: Bool? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.context = context
        self.include = include
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.verdictOnly = verdictOnly
        self.flagProfanity = flagProfanity
        self.flagRiskTerms = flagRiskTerms
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from combined safety analysis.
public struct AnalyzeResult: Codable, Sendable {
    public let riskLevel: RiskLevel
    public let riskScore: Double
    /// Highest confidence across the included sub-results.
    public let confidence: Double
    public let summary: String
    public let bullying: BullyingResult?
    public let unsafe: UnsafeResult?
    /// Strongest recommended action across the included sub-results.
    public let recommendedAction: RecommendedAction
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?
    public let incidentModerationEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case riskLevel = "risk_level"
        case riskScore = "risk_score"
        case confidence, summary, bullying, unsafe
        case recommendedAction = "recommended_action"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
        case incidentModerationEnabled = "incident_moderation_enabled"
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
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case dominantEmotions = "dominant_emotions"
        case emotionScores = "emotion_scores"
        case trend, summary
        case recommendedFollowup = "recommended_followup"
        case creditsUsed = "credits_used"
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
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        situation: String,
        childAge: Int? = nil,
        audience: Audience? = nil,
        severity: Severity? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.situation = situation
        self.childAge = childAge
        self.audience = audience
        self.severity = severity
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from action plan generation.
public struct ActionPlanResult: Codable, Sendable {
    public let audience: String
    public let steps: [String]
    public let tone: String
    public let readingLevel: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case audience, steps, tone
        case readingLevel = "approx_reading_level"
        case creditsUsed = "credits_used"
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
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        messages: [ReportMessage],
        childAge: Int? = nil,
        incidentType: String? = nil,
        conversationId: String? = nil,
        timestampRange: [String]? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.messages = messages
        self.childAge = childAge
        self.incidentType = incidentType
        self.conversationId = conversationId
        self.timestampRange = timestampRange
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Result from incident report generation.
public struct ReportResult: Codable, Sendable {
    public let summary: String
    public let riskLevel: RiskLevel
    public let categories: [String]
    public let recommendedNextSteps: [String]
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case summary, categories
        case riskLevel = "risk_level"
        case recommendedNextSteps = "recommended_next_steps"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Voice Analysis

/// A timestamped segment from audio transcription.
public struct TranscriptionSegment: Codable, Sendable {
    /// Start time in seconds.
    public let start: Double
    /// End time in seconds.
    public let end: Double
    /// Transcribed text for this segment.
    public let text: String
}

/// Result from audio transcription.
public struct TranscriptionResult: Codable, Sendable {
    /// Full transcribed text.
    public let text: String
    /// Detected language code.
    public let language: String
    /// Audio duration in seconds.
    public let duration: Double
    /// Timestamped segments. Empty when the audio has no intelligible speech.
    public let segments: [TranscriptionSegment]

    public init(text: String, language: String, duration: Double, segments: [TranscriptionSegment]) {
        self.text = text
        self.language = language
        self.duration = duration
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case text, language, duration, segments
    }

    /// The API leaves `segments` out when there is no speech, and out of a video's transcription.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        language = try container.decode(String.self, forKey: .language)
        duration = try container.decode(Double.self, forKey: .duration)
        segments = try container.decodeIfPresent([TranscriptionSegment].self, forKey: .segments) ?? []
    }
}

/// Input for voice analysis.
///
/// Provide audio file data and an optional analysis type. The SDK handles
/// multipart encoding and MIME type detection from the filename extension.
///
/// ```swift
/// let audioData = try Data(contentsOf: audioURL)
/// let input = AnalyzeVoiceInput(file: audioData, filename: "recording.mp3")
/// let result = try await tuteliq.analyzeVoice(input)
/// ```
public struct AnalyzeVoiceInput: Sendable {
    /// Raw audio file data.
    public var file: Data
    /// Filename with extension (used for MIME type detection).
    public var filename: String
    /// Analysis type to run on the transcript. Defaults to `.all`.
    public var analysisType: VoiceAnalysisType?
    /// Customer-provided file reference echoed in the response.
    public var fileId: String?
    /// Age group range (e.g., `"11-13"`).
    public var ageGroup: String?
    /// Language code (e.g., `"en"`).
    public var language: String?
    /// Platform where the content originated.
    public var platform: String?
    /// Age of the child participant.
    public var childAge: Int?
    /// Your external correlation ID (max 255 chars).
    public var externalId: String?
    /// Multi-tenant customer ID for webhook routing (max 255 chars).
    public var customerId: String?
    /// Arbitrary key-value metadata as a JSON string map.
    public var metadata: [String: String]?

    public init(
        file: Data,
        filename: String,
        analysisType: VoiceAnalysisType? = nil,
        fileId: String? = nil,
        ageGroup: String? = nil,
        language: String? = nil,
        platform: String? = nil,
        childAge: Int? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.file = file
        self.filename = filename
        self.analysisType = analysisType
        self.fileId = fileId
        self.ageGroup = ageGroup
        self.language = language
        self.platform = platform
        self.childAge = childAge
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata
    }
}

/// Result from voice analysis.
public struct VoiceAnalysisResult: Codable, Sendable {
    /// Customer-provided file reference.
    public let fileId: String?
    /// Transcription with timestamped segments.
    public let transcription: TranscriptionResult
    /// Per-type analysis results (keys: `bullying`, `unsafe`, `grooming`, `emotions`).
    public let analysis: [String: AnyCodable]?
    /// Overall risk score (0.0–1.0).
    public let overallRiskScore: Double
    /// Overall severity level. `none` for silent or benign audio.
    public let overallSeverity: ContentSeverity
    /// A concern was observed at any severity, including monitor-only. Prefer `recommendedAction` for branching.
    public let detected: Bool
    /// Confidence in the overall verdict (0.0–1.0).
    public let confidence: Double
    /// Routing key, matching every other detection endpoint.
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    /// Why this verdict was reached. Built from labels only; never contains the transcript.
    public let rationale: String
    /// Number of credits consumed by this request.
    public let creditsUsed: Int?
    /// Echoed external correlation ID.
    public let externalId: String?
    /// Echoed customer ID.
    public let customerId: String?
    /// Echoed metadata.
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case transcription, analysis
        case overallRiskScore = "overall_risk_score"
        case overallSeverity = "overall_severity"
        case detected, confidence, rationale, metadata
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}

// MARK: - Image Analysis

/// Visual analysis result from image safety classification and OCR.
public struct VisionResult: Codable, Sendable {
    /// Text extracted via OCR.
    public let extractedText: String
    /// Visual harm categories detected.
    public let visualCategories: [String]
    /// Visual content severity.
    public let visualSeverity: ContentSeverity
    /// Confidence score (0.0–1.0).
    public let visualConfidence: Double
    /// Description of visual content.
    public let visualDescription: String
    /// Whether the image contains readable text.
    public let containsText: Bool
    /// Whether the image contains faces.
    public let containsFaces: Bool

    enum CodingKeys: String, CodingKey {
        case extractedText = "extracted_text"
        case visualCategories = "visual_categories"
        case visualSeverity = "visual_severity"
        case visualConfidence = "visual_confidence"
        case visualDescription = "visual_description"
        case containsText = "contains_text"
        case containsFaces = "contains_faces"
    }
}

/// Input for image analysis.
///
/// Provide image file data and an optional analysis type. The SDK handles
/// multipart encoding and MIME type detection from the filename extension.
///
/// ```swift
/// let imageData = try Data(contentsOf: imageURL)
/// let input = AnalyzeImageInput(file: imageData, filename: "screenshot.png")
/// let result = try await tuteliq.analyzeImage(input)
/// ```
public struct AnalyzeImageInput: Sendable {
    /// Raw image file data.
    public var file: Data
    /// Filename with extension (used for MIME type detection).
    public var filename: String
    /// Analysis type to run on extracted text. Defaults to `.all`.
    public var analysisType: ImageAnalysisType?
    /// Customer-provided file reference echoed in the response.
    public var fileId: String?
    /// Age group range (e.g., `"11-13"`).
    public var ageGroup: String?
    /// Platform where the content originated.
    public var platform: String?
    /// Your external correlation ID (max 255 chars).
    public var externalId: String?
    /// Multi-tenant customer ID for webhook routing (max 255 chars).
    public var customerId: String?
    /// Arbitrary key-value metadata as a JSON string map.
    public var metadata: [String: String]?
    /// Adds a deterministic `profanity` result over the OCR'd text. Only meaningful
    /// when the image contains text. `nil` uses the account default.
    public var flagProfanity: Bool?

    public init(
        file: Data,
        filename: String,
        analysisType: ImageAnalysisType? = nil,
        fileId: String? = nil,
        ageGroup: String? = nil,
        platform: String? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: String]? = nil,
        flagProfanity: Bool? = nil
    ) {
        self.file = file
        self.filename = filename
        self.analysisType = analysisType
        self.fileId = fileId
        self.ageGroup = ageGroup
        self.platform = platform
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata
        self.flagProfanity = flagProfanity
    }
}

/// Result from image analysis.
///
/// Animated GIFs are analysed frame by frame; send the original GIF rather than a still.
public struct ImageAnalysisResult: Codable, Sendable {
    /// Customer-provided file reference.
    public let fileId: String?
    /// Vision analysis with OCR and visual classification.
    public let vision: VisionResult
    /// Per-type text analysis results from extracted OCR text (keys: `bullying`, `unsafe`, `emotions`).
    public let textAnalysis: [String: AnyCodable]?
    /// Overall risk score (0.0–1.0).
    public let overallRiskScore: Double
    /// Overall severity level.
    public let overallSeverity: ContentSeverity
    /// A concern was observed at any severity. Prefer `recommendedAction` for branching.
    public let detected: Bool
    /// Confidence in the overall verdict (0.0–1.0).
    public let confidence: Double
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    /// Why this verdict was reached. Built from labels only.
    public let rationale: String
    /// Present when `flagProfanity` (or the account default) is on and the image contains text.
    public let profanity: ProfanityResult?
    /// Number of credits consumed by this request.
    public let creditsUsed: Int?
    /// Echoed external correlation ID.
    public let externalId: String?
    /// Echoed customer ID.
    public let customerId: String?
    /// Echoed metadata.
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case vision
        case textAnalysis = "text_analysis"
        case overallRiskScore = "overall_risk_score"
        case overallSeverity = "overall_severity"
        case detected, confidence, rationale, profanity, metadata
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}

// MARK: - Unified Detection (Fraud + Safety Extended)

/// Input for all fraud detection and safety-extended endpoints.
public struct DetectionInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Optional analysis context. `priorMessages` is supported on this endpoint family.
    public var context: AnalysisContext?
    /// Include evidence excerpts (quoted spans of the input). `nil` lets the API decide:
    /// `true` normally, `false` when `verdictOnly` is set. An explicit value always wins.
    public var includeEvidence: Bool?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?
    /// Minimum severity to include crisis support resources (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Fast mode: omits `messageAnalysis`, and `evidence` unless `includeEvidence` is set.
    /// `rationale` and the verdict are always generated.
    public var verdictOnly: Bool
    /// Token from a previous call to the same endpoint. The conversation-aware
    /// endpoints (coercive control, vulnerability exploitation, distress signals)
    /// return a fresh one on every result.
    public var continuationToken: String?
    /// Discard any `continuationToken` and start a fresh conversation.
    public var resetConversation: Bool
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        includeEvidence: Bool? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        supportThreshold: SupportThreshold? = nil,
        verdictOnly: Bool = false,
        continuationToken: String? = nil,
        resetConversation: Bool = false,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.context = context
        self.includeEvidence = includeEvidence
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.supportThreshold = supportThreshold
        self.verdictOnly = verdictOnly
        self.continuationToken = continuationToken
        self.resetConversation = resetConversation
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Per-message analysis from conversation-aware detection.
public struct MessageAnalysis: Codable, Sendable {
    /// Index of the message in the input array.
    public let messageIndex: Int
    /// Risk score for this specific message (0.0–1.0).
    public let riskScore: Double
    /// Flags identified in this message.
    public let flags: [String]
    /// Brief summary of the message analysis.
    public let summary: String

    enum CodingKeys: String, CodingKey {
        case messageIndex = "message_index"
        case riskScore = "risk_score"
        case flags, summary
    }
}

/// A detected category with tag and confidence.
public struct DetectionCategory: Codable, Sendable {
    public let tag: String
    public let label: String
    public let confidence: Double
}

/// Evidence excerpt from the analyzed content.
public struct DetectionEvidence: Codable, Sendable {
    public let text: String
    public let tactic: String
    public let weight: Double
}

/// Age calibration details applied to risk scoring.
public struct AgeCalibration: Codable, Sendable {
    public let applied: Bool
    public let ageGroup: String?
    public let multiplier: Double?

    enum CodingKeys: String, CodingKey {
        case applied
        case ageGroup = "age_group"
        case multiplier
    }
}

/// Unified result from fraud detection and safety-extended endpoints.
public struct DetectionResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let confidence: Double
    public let riskScore: Double
    /// `none` / `low` / `medium` / `high` / `critical`.
    public let level: String
    public let categories: [DetectionCategory]
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    public let rationale: String?
    /// Absent when no supported language was resolved (an unsupported language, or a very short text).
    public let language: String?
    public let languageStatus: LanguageStatus?
    /// Omitted when `includeEvidence` is false, including implicitly via `verdictOnly`.
    public let evidence: [DetectionEvidence]?
    public let ageCalibration: AgeCalibration?
    public let messageAnalysis: [MessageAnalysis]?
    public let creditsUsed: Int?
    public let processingTimeMs: Double?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?
    public let continuationToken: String?
    public let continuationExpiresAt: String?
    public let stateSource: StateSource?
    /// Conversation-level risk (0–1) on the conversation-aware endpoints. Absent on the first turn.
    public let trajectoryRisk: Double?
    public let trajectory: ConversationTrajectory?
    public let severitySeries: [Double]?
    public let support: SupportData?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, confidence, categories, rationale, language, evidence, metadata
        case riskScore = "risk_score"
        case level
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case languageStatus = "language_status"
        case ageCalibration = "age_calibration"
        case messageAnalysis = "message_analysis"
        case creditsUsed = "credits_used"
        case processingTimeMs = "processing_time_ms"
        case externalId = "external_id"
        case customerId = "customer_id"
        case continuationToken = "continuation_token"
        case continuationExpiresAt = "continuation_expires_at"
        case stateSource = "state_source"
        case trajectoryRisk = "trajectory_risk"
        case trajectory
        case severitySeries = "severity_series"
        case support
    }
}

// MARK: - Multi-Endpoint Analysis

/// Input for multi-endpoint analysis.
public struct AnalyseMultiInput: Sendable {
    /// Text content to analyze.
    public var content: String
    /// Detection endpoints to run (max 10).
    public var detections: [Detection]
    /// Optional analysis context.
    public var context: AnalysisContext?
    /// Include evidence in individual results.
    public var includeEvidence: Bool
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: AnyCodable]?
    /// Minimum severity to include crisis support resources (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Fast mode: individual results omit `messageAnalysis`.
    public var verdictOnly: Bool
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        detections: [Detection],
        context: AnalysisContext? = nil,
        includeEvidence: Bool = false,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        supportThreshold: SupportThreshold? = nil,
        verdictOnly: Bool = false,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.detections = detections
        self.context = context
        self.includeEvidence = includeEvidence
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.supportThreshold = supportThreshold
        self.verdictOnly = verdictOnly
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// The endpoint with the highest risk in a multi-endpoint analysis.
public struct AnalyseMultiHighestRisk: Codable, Sendable {
    public let endpoint: String
    public let riskScore: Double

    enum CodingKeys: String, CodingKey {
        case endpoint
        case riskScore = "risk_score"
    }
}

/// Summary of multi-endpoint analysis results.
public struct AnalyseMultiSummary: Codable, Sendable {
    public let totalEndpoints: Int
    public let detectedCount: Int
    public let highestRisk: AnalyseMultiHighestRisk
    public let overallRiskLevel: String

    enum CodingKeys: String, CodingKey {
        case totalEndpoints = "total_endpoints"
        case detectedCount = "detected_count"
        case highestRisk = "highest_risk"
        case overallRiskLevel = "overall_risk_level"
    }
}

/// Result from multi-endpoint analysis.
/// One detector's verdict inside ``AnalyseMultiResult``.
///
/// Leaner than ``DetectionResult``: a multi result carries no language, and
/// `confidence` and `riskScore` only when that detector reports them.
public struct AnalyseMultiEndpointResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let confidence: Double?
    public let riskScore: Double?
    /// `none` / `low` / `medium` / `high` / `critical`.
    public let level: String
    public let categories: [DetectionCategory]
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    public let rationale: String?
    /// Omitted when `includeEvidence` is false.
    public let evidence: [DetectionEvidence]?
    public let ageCalibration: AgeCalibration?
    public let crossEndpointModifier: Double?
    public let creditsUsed: Int?
    public let processingTimeMs: Double?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, confidence, level, categories, rationale, evidence
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case ageCalibration = "age_calibration"
        case crossEndpointModifier = "cross_endpoint_modifier"
        case creditsUsed = "credits_used"
        case processingTimeMs = "processing_time_ms"
    }
}

public struct AnalyseMultiResult: Codable, Sendable {
    public let results: [AnalyseMultiEndpointResult]
    public let summary: AnalyseMultiSummary
    public let crossEndpointModifier: Double?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case results, summary, metadata
        case crossEndpointModifier = "cross_endpoint_modifier"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}

// MARK: - Video Analysis

/// Per-frame analysis, one entry per sampled frame.
public struct VideoFrameResult: Codable, Sendable {
    public let frameIndex: Int
    /// Position of the frame in the video, in seconds.
    public let timestampSeconds: Double
    public let vision: VisionResult
    public let riskScore: Double
    public let severity: ContentSeverity

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case timestampSeconds = "timestamp_s"
        case vision
        case riskScore = "risk_score"
        case severity
    }
}

/// A point in the video that exceeded the reporting threshold.
public struct VideoFlaggedTimestamp: Codable, Sendable {
    /// Position in the video, in seconds.
    public let timestampSeconds: Double
    /// Categories detected at this timestamp.
    public let reason: String
    public let severity: ContentSeverity

    enum CodingKeys: String, CodingKey {
        case timestampSeconds = "timestamp_s"
        case reason, severity
    }
}

/// Input for video analysis.
public struct AnalyzeVideoInput: Sendable {
    /// Raw video file data.
    public var file: Data
    /// Filename with extension (used for MIME type detection).
    public var filename: String
    /// Customer-provided file reference echoed in the response.
    public var fileId: String?
    /// Age group range.
    public var ageGroup: String?
    /// Platform where the content originated.
    public var platform: String?
    /// Your external correlation ID.
    public var externalId: String?
    /// Multi-tenant customer ID.
    public var customerId: String?
    /// Arbitrary key-value metadata.
    public var metadata: [String: String]?
    /// Adds a deterministic `profanity` result over on-screen text across frames.
    /// Only meaningful when the video contains text. `nil` uses the account default.
    public var flagProfanity: Bool?

    public init(
        file: Data,
        filename: String,
        fileId: String? = nil,
        ageGroup: String? = nil,
        platform: String? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: String]? = nil,
        flagProfanity: Bool? = nil
    ) {
        self.file = file
        self.filename = filename
        self.fileId = fileId
        self.ageGroup = ageGroup
        self.platform = platform
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata
        self.flagProfanity = flagProfanity
    }
}

/// Result from video analysis.
public struct VideoAnalysisResult: Codable, Sendable {
    public let fileId: String?
    public let framesAnalyzed: Int
    public let durationSeconds: Double
    public let frameResults: [VideoFrameResult]
    /// Visual harm categories across every flagged frame, deduped.
    /// `nil` against API deployments before 2026-08-26.
    public let categories: [String]?
    public let flaggedTimestamps: [VideoFlaggedTimestamp]
    public let overallRiskScore: Double
    public let overallSeverity: ContentSeverity
    /// A concern was observed at any severity. Prefer `recommendedAction` for branching.
    public let detected: Bool
    public let confidence: Double
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    /// Why this verdict was reached. Built from labels only.
    public let rationale: String
    /// Present when `flagProfanity` (or the account default) is on and a frame contains text.
    public let profanity: ProfanityResult?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case framesAnalyzed = "frames_analyzed"
        case durationSeconds = "duration_seconds"
        case frameResults = "frame_results"
        case categories
        case flaggedTimestamps = "flagged_timestamps"
        case overallRiskScore = "overall_risk_score"
        case overallSeverity = "overall_severity"
        case detected, confidence, rationale, profanity
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

// MARK: - Verification

/// Input for creating a verification session.
public struct CreateVerificationSessionInput: Sendable {
    /// Verification mode (age or identity).
    public var mode: VerificationMode
    /// Document type to verify.
    public var documentType: DocumentType?

    public init(mode: VerificationMode, documentType: DocumentType? = nil) {
        self.mode = mode
        self.documentType = documentType
    }
}

/// Verification session details.
public struct VerificationSession: Codable, Sendable {
    public let sessionId: String
    /// URL to open in a browser or web view for the user to complete verification
    /// (the API's `mobile_url`). Carries the session token; treat it as a secret.
    public let url: String
    /// Epoch **milliseconds** at which the session expires.
    public let expiresAt: Int64
    public let mode: VerificationMode
    /// Which checks the session runs: `"full"` or `"liveness_only"`.
    public let verificationMode: String?
    /// Camera capture width the API recommends, in pixels.
    public let recommendedImageWidth: Int?

    /// ``expiresAt`` as a `Date`.
    public var expiresAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case url = "mobile_url"
        case expiresAt = "expires_at"
        case mode
        case verificationMode = "verification_mode"
        case recommendedImageWidth = "recommended_image_width"
    }
}

/// Face match result from verification.
public struct FaceMatchResult: Codable, Sendable {
    public let matched: Bool
    public let confidence: Double
    /// Distance between face descriptors (lower is more similar). Not returned by every endpoint.
    public let distance: Double?
}

/// Liveness check result from verification.
public struct LivenessResult: Codable, Sendable {
    public let valid: Bool
    public let reason: String?
}

/// A national ID number extracted from a document.
public struct NationalIdNumber: Codable, Sendable {
    public let value: String
    /// Whether the number passed its country's algorithmic check.
    public let valid: Bool
    public let type: String
    public let countryCode: String

    enum CodingKeys: String, CodingKey {
        case value, valid, type
        case countryCode = "country_code"
    }
}

/// Parsed MRZ (machine-readable zone) fields, check-digit validated where applicable.
public struct MrzFields: Codable, Sendable {
    public let documentNumber: String?
    /// Three-letter nationality code.
    public let nationality: String?
    /// `YYYY-MM-DD`.
    public let dateOfBirth: String?
    /// `YYYY-MM-DD`.
    public let expiryDate: String?
    public let sex: String?
    public let surname: String?
    public let givenNames: String?

    enum CodingKeys: String, CodingKey {
        case documentNumber = "document_number"
        case nationality
        case dateOfBirth = "date_of_birth"
        case expiryDate = "expiry_date"
        case sex, surname
        case givenNames = "given_names"
    }
}

/// Document fields extracted during verification.
///
/// Returned in full on the first poll of a finished session, and from
/// ``Tuteliq/submitVerification(_:)``. Every field is optional because each
/// document type exposes a different subset.
public struct VerificationDocument: Codable, Sendable {
    public let ocrConfidence: Double?
    public let nameExtracted: String?
    public let firstName: String?
    public let lastName: String?
    public let dobExtracted: String?
    public let documentNumber: String?
    /// Whether the document number passed algorithmic validation.
    public let documentNumberValid: Bool?
    public let sex: String?
    public let countryCode: String?
    public let countryName: String?
    public let documentType: String?
    public let expirationDate: String?
    public let expired: Bool?
    public let issueDate: String?
    public let heightCm: Double?
    public let placeOfBirth: String?
    public let nationality: String?
    public let issuingAuthority: String?
    public let nationalId: NationalIdNumber?
    /// Whether MRZ check digits passed. Only on `submitVerification`; `nil` when there is no MRZ.
    public let mrzValid: Bool?
    /// Parsed MRZ. Only on `submitVerification`.
    public let mrzFields: MrzFields?
    /// The MRZ and portrait came from the document's NFC chip and passed passive
    /// authentication (the signed data groups are intact).
    public let chipVerified: Bool?
    /// The chip's Document Signer chains to a trusted country signing CA. `nil`
    /// when the chip was not used or the server has no trust list configured.
    public let chipIssuerTrusted: Bool?

    enum CodingKeys: String, CodingKey {
        case ocrConfidence = "ocr_confidence"
        case nameExtracted = "name_extracted"
        case firstName = "first_name"
        case lastName = "last_name"
        case dobExtracted = "dob_extracted"
        case documentNumber = "document_number"
        case documentNumberValid = "document_number_valid"
        case sex
        case countryCode = "country_code"
        case countryName = "country_name"
        case documentType = "document_type"
        case expirationDate = "expiration_date"
        case expired
        case issueDate = "issue_date"
        case heightCm = "height_cm"
        case placeOfBirth = "place_of_birth"
        case nationality
        case issuingAuthority = "issuing_authority"
        case nationalId = "national_id"
        case mrzValid = "mrz_valid"
        case mrzFields = "mrz_fields"
        case chipVerified = "chip_verified"
        case chipIssuerTrusted = "chip_issuer_trusted"
    }
}

/// The verification outcome carried on a finished session.
public struct VerificationResult: Codable, Sendable {
    public let status: VerificationStatus
    public let age: Int?
    /// `YYYY-MM-DD`.
    public let dateOfBirth: String?
    public let isMinor: Bool?
    public let faceMatch: FaceMatchResult?
    public let liveness: LivenessResult
    public let failureReasons: [String]?
    /// Extracted KYC fields. Only present on the first poll after the session
    /// finishes; later polls return the decision only.
    public let document: VerificationDocument?

    enum CodingKeys: String, CodingKey {
        case status, age, liveness, document
        case dateOfBirth = "date_of_birth"
        case isMinor = "is_minor"
        case faceMatch = "face_match"
        case failureReasons = "failure_reasons"
    }
}

/// Result of polling a verification session.
public struct VerificationSessionResult: Codable, Sendable {
    public let sessionId: String
    public let status: VerificationSessionStatus
    /// Present once the session is `completed` or `failed`.
    public let result: VerificationResult?
    /// Current step reported by the capture device (e.g. `"selfie"`, `"submitting"`).
    public let stepProgress: String?
    /// Epoch milliseconds.
    public let createdAt: Int64?
    /// Epoch milliseconds.
    public let expiresAt: Int64?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status, result
        case stepProgress = "step_progress"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// Result of retrieving an age verification by ID.
public struct VerificationRetrieveResult: Codable, Sendable {
    public let verificationId: String
    public let status: VerificationStatus
    public let isMinor: Bool?
    public let faceMatched: Bool?
    public let livenessValid: Bool
    public let failureReasons: [String]
    /// ISO 8601.
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case verificationId = "verification_id"
        case status
        case isMinor = "is_minor"
        case faceMatched = "face_matched"
        case livenessValid = "liveness_valid"
        case failureReasons = "failure_reasons"
        case createdAt = "created_at"
    }
}

/// Result of retrieving an identity verification by ID.
public struct IdentityRetrieveResult: Codable, Sendable {
    public let verificationId: String
    public let status: VerificationStatus
    public let faceMatched: Bool?
    public let faceConfidence: Double?
    public let livenessValid: Bool
    public let failureReasons: [String]
    /// ISO 8601.
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case verificationId = "verification_id"
        case status
        case faceMatched = "face_matched"
        case faceConfidence = "face_confidence"
        case livenessValid = "liveness_valid"
        case failureReasons = "failure_reasons"
        case createdAt = "created_at"
    }
}

/// Result of cancelling a verification session. The session moves to `expired`.
public struct CancelVerificationSessionResult: Codable, Sendable {
    public let ok: Bool
}

/// Server-issued liveness challenge.
///
/// Returned from ``Tuteliq/getLivenessChallenge()``. The signature is an HMAC
/// computed over the nonce + expiry + ordered challenges, so the client MUST
/// run the prompts in the order returned. Re-ordering will fail server-side
/// validation.
public struct LivenessChallenge: Codable, Sendable, Equatable {
    /// Opaque server-generated nonce (UUID).
    public let nonce: String
    /// HMAC-SHA256 of `nonce + ":" + expiresAt + ":" + challenges.joined(",")`.
    public let signature: String
    /// Unix-**milliseconds** timestamp at which the challenge expires.
    /// The server emits `Date.now() + livenessTokenMaxAgeMs` (default 5 min).
    public let expiresAt: Int64
    /// Ordered list of challenge prompts. The pool is `"center"` (always
    /// first, calibration), then a shuffled mix of `"left"`, `"right"`,
    /// `"blink"`, `"smile"`. Run them in this order.
    public let challenges: [String]

    public init(nonce: String, signature: String, expiresAt: Int64, challenges: [String]) {
        self.nonce = nonce
        self.signature = signature
        self.expiresAt = expiresAt
        self.challenges = challenges
    }

    enum CodingKeys: String, CodingKey {
        case nonce, signature, challenges
        case expiresAt = "expires_at"
    }
}

/// Input to ``Tuteliq/submitVerification(_:)``.
///
/// Provide either `passport` (preferred when available) **or** `idFront` +
/// `idBack` for two-sided ID cards / driving licences. `selfie` and
/// `livenessToken` are always required.
public struct SubmitVerificationInput: Sendable {
    /// JPEG bytes of the passport bio page. Mutually exclusive with `idFront`/`idBack`.
    public var passport: Data?
    /// JPEG bytes of the front of an ID card or driving licence.
    public var idFront: Data?
    /// JPEG bytes of the back of an ID card or driving licence.
    public var idBack: Data?
    /// JPEG bytes of the selfie capture.
    public var selfie: Data
    /// Stringified `LivenessToken` payload built from the server's
    /// `LivenessChallenge` and the client's challenge timestamps. The full
    /// payload (nonce, signature, expires_at, challenges with completedAt) is
    /// expected; see the production web flow for the exact shape.
    public var livenessToken: String
    /// Optional individual JPEG frames captured during liveness — strengthens
    /// anti-spoofing when supplied.
    public var livenessFrames: [Data]?

    public init(
        passport: Data? = nil,
        idFront: Data? = nil,
        idBack: Data? = nil,
        selfie: Data,
        livenessToken: String,
        livenessFrames: [Data]? = nil
    ) {
        self.passport = passport
        self.idFront = idFront
        self.idBack = idBack
        self.selfie = selfie
        self.livenessToken = livenessToken
        self.livenessFrames = livenessFrames
    }
}

/// Response from ``Tuteliq/submitVerification(_:)``.
public struct VerificationSubmitResult: Codable, Sendable {
    public let verificationId: String?
    public let status: VerificationStatus
    public let age: Int?
    public let dateOfBirth: String?
    public let isMinor: Bool?
    public let document: VerificationDocument?
    public let faceMatch: FaceMatchResult?
    public let liveness: LivenessResult
    public let creditsUsed: Int?

    enum CodingKeys: String, CodingKey {
        case verificationId = "verification_id"
        case status, age, document, liveness
        case dateOfBirth = "date_of_birth"
        case isMinor = "is_minor"
        case faceMatch = "face_match"
        case creditsUsed = "credits_used"
    }
}

// MARK: - Document Analysis

/// Input for document (PDF) analysis.
///
/// Provide PDF file data and optional detection endpoints. The SDK handles
/// multipart encoding and MIME type detection from the filename extension.
///
/// ```swift
/// let pdfData = try Data(contentsOf: pdfURL)
/// let input = AnalyzeDocumentInput(file: pdfData, filename: "report.pdf")
/// let result = try await tuteliq.analyzeDocument(input)
/// ```
public struct AnalyzeDocumentInput: Sendable {
    /// Raw PDF file data.
    public var file: Data
    /// Filename with extension (used for MIME type detection).
    public var filename: String
    /// Detection endpoints to run on each page. Defaults to `["unsafe", "coercive-control", "radicalisation"]`.
    public var endpoints: [DocumentEndpointName]?
    /// Customer-provided file reference echoed in the response.
    public var fileId: String?
    /// Age group range (e.g., `"11-13"`).
    public var ageGroup: String?
    /// Language hint (ISO 639-1).
    public var language: String?
    /// Platform where the content originated.
    public var platform: String?
    /// Minimum severity to include crisis helplines (API default: `.high`).
    public var supportThreshold: SupportThreshold?
    /// Your external correlation ID (max 255 chars).
    public var externalId: String?
    /// Multi-tenant customer ID for webhook routing (max 255 chars).
    public var customerId: String?
    /// Arbitrary key-value metadata as a JSON string map.
    public var metadata: [String: String]?

    public init(
        file: Data,
        filename: String,
        endpoints: [DocumentEndpointName]? = nil,
        fileId: String? = nil,
        ageGroup: String? = nil,
        language: String? = nil,
        platform: String? = nil,
        supportThreshold: SupportThreshold? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.file = file
        self.filename = filename
        self.endpoints = endpoints
        self.fileId = fileId
        self.ageGroup = ageGroup
        self.language = language
        self.platform = platform
        self.supportThreshold = supportThreshold
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata
    }
}

/// Breakdown of text extraction results across document pages.
public struct DocumentExtractionSummary: Codable, Sendable {
    /// Pages where text was extracted from the PDF text layer.
    public let textLayerPages: Int
    /// Pages where OCR was used.
    public let ocrPages: Int
    /// Pages with insufficient text for analysis.
    public let failedPages: Int
    /// Average OCR confidence (0.0–1.0) across OCR pages.
    public let averageOcrConfidence: Double

    enum CodingKeys: String, CodingKey {
        case textLayerPages = "text_layer_pages"
        case ocrPages = "ocr_pages"
        case failedPages = "failed_pages"
        case averageOcrConfidence = "average_ocr_confidence"
    }
}

/// Category detected within a document page endpoint result.
public struct DocumentCategory: Codable, Sendable {
    /// Category tag identifier.
    public let tag: String
    /// Human-readable label.
    public let label: String
    /// Confidence score (0.0–1.0).
    public let confidence: Double
}

/// Evidence excerpt from a document page endpoint result.
public struct DocumentEvidence: Codable, Sendable {
    /// Relevant text excerpt.
    public let text: String
    /// Detected tactic or pattern.
    public let tactic: String
    /// Evidence weight (0.0–1.0).
    public let weight: Double
}

/// Detection result for a single endpoint on a single document page.
public struct DocumentPageEndpointResult: Codable, Sendable {
    /// Endpoint name.
    public let endpoint: String
    /// Whether a threat was detected.
    public let detected: Bool
    /// Severity score (0.0–1.0).
    public let severity: Double
    /// Confidence score (0.0–1.0).
    public let confidence: Double
    /// Risk score (0.0–1.0).
    public let riskScore: Double
    /// Risk level.
    public let level: String
    /// Detected categories.
    public let categories: [DocumentCategory]
    /// Evidence excerpts.
    public let evidence: [DocumentEvidence]
    /// Recommended action for this endpoint on this page.
    public let recommendedAction: RecommendedAction
    /// Human-readable expansion of `recommendedAction`. Do not branch on it.
    public let actionDetail: String?
    /// Human-readable rationale.
    public let rationale: String
    /// Detected language.
    public let detectedLanguage: String?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, confidence
        case riskScore = "risk_score"
        case level, categories, evidence
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case rationale
        case detectedLanguage = "detected_language"
    }
}

/// Detection results for a single document page.
public struct DocumentPageResult: Codable, Sendable {
    /// Page number (1-indexed).
    public let pageNumber: Int
    /// First 200 characters of page text.
    public let textPreview: String
    /// How text was extracted (`"text_layer"` or `"ocr"`).
    public let extractionMethod: String
    /// OCR confidence if applicable.
    public let ocrConfidence: Double?
    /// Detection results per endpoint.
    public let results: [DocumentPageEndpointResult]
    /// Highest risk score on this page.
    public let pageRiskScore: Double
    /// Page severity level.
    public let pageSeverity: String

    enum CodingKeys: String, CodingKey {
        case pageNumber = "page_number"
        case textPreview = "text_preview"
        case extractionMethod = "extraction_method"
        case ocrConfidence = "ocr_confidence"
        case results
        case pageRiskScore = "page_risk_score"
        case pageSeverity = "page_severity"
    }
}

/// A flagged page with elevated risk.
public struct DocumentFlaggedPage: Codable, Sendable {
    /// Page number.
    public let pageNumber: Int
    /// Risk score.
    public let riskScore: Double
    /// Severity level.
    public let severity: String
    /// Endpoints that detected threats on this page.
    public let detectedEndpoints: [String]

    enum CodingKeys: String, CodingKey {
        case pageNumber = "page_number"
        case riskScore = "risk_score"
        case severity
        case detectedEndpoints = "detected_endpoints"
    }
}

/// Result from document (PDF) analysis.
public struct DocumentAnalysisResult: Codable, Sendable {
    /// Customer-provided file reference (if provided).
    public let fileId: String?
    /// SHA-256 hash of the uploaded PDF for chain-of-custody verification.
    public let documentHash: String
    /// Total pages in the document.
    public let totalPages: Int
    /// Pages with extractable text that were analyzed.
    public let pagesAnalyzed: Int
    /// Breakdown of text extraction results.
    public let extractionSummary: DocumentExtractionSummary
    /// Per-page detection results.
    public let pageResults: [DocumentPageResult]
    /// Highest risk score across all pages (0.0–1.0).
    public let overallRiskScore: Double
    /// Overall severity level.
    public let overallSeverity: String
    /// Unique list of endpoints that detected threats.
    public let detectedEndpoints: [String]
    /// Pages with risk score >= 0.3.
    public let flaggedPages: [DocumentFlaggedPage]
    /// Dynamic credit cost based on pages analyzed and endpoints used.
    public let creditsUsed: Int
    /// Processing time in milliseconds.
    public let processingTimeMs: Int
    /// Detected language.
    public let language: String?
    /// Language support status.
    public let languageStatus: String?
    /// Crisis support resources (if triggered).
    public let support: [String: AnyCodable]?
    /// Echoed external correlation ID.
    public let externalId: String?
    /// Echoed customer ID.
    public let customerId: String?
    /// Echoed metadata.
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case documentHash = "document_hash"
        case totalPages = "total_pages"
        case pagesAnalyzed = "pages_analyzed"
        case extractionSummary = "extraction_summary"
        case pageResults = "page_results"
        case overallRiskScore = "overall_risk_score"
        case overallSeverity = "overall_severity"
        case detectedEndpoints = "detected_endpoints"
        case flaggedPages = "flagged_pages"
        case creditsUsed = "credits_used"
        case processingTimeMs = "processing_time_ms"
        case language
        case languageStatus = "language_status"
        case support
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
