import Foundation

/// Severity levels for detected content.
public enum Severity: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

/// Grooming risk levels.
public enum GroomingRisk: String, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case critical
}

/// Overall risk levels.
public enum RiskLevel: String, Codable, Sendable {
    case safe
    case low
    case medium
    case high
    case critical
}

/// Emotion trend direction.
public enum EmotionTrend: String, Codable, Sendable {
    case improving
    case stable
    case worsening
}

/// Target audience for action plans.
///
/// Maps to the API `role` field on `POST /api/v1/guidance/action-plan`.
public enum Audience: String, Codable, Sendable {
    case child
    case parent
    case platform
}

/// Message role in grooming detection conversations.
public enum MessageRole: String, Codable, Sendable {
    case adult
    case child
    case unknown
}

/// Analysis types for batch and quick analysis.
public enum AnalysisType: String, Codable, Sendable {
    case bullying
    case unsafe
    case grooming
    case emotions
    case voice
    case image
}

/// Severity levels that include `none` — used for visual and overall media analysis.
public enum ContentSeverity: String, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case critical
}

/// The action Tuteliq recommends, ordered weakest to strongest.
///
/// This is the field to branch on: it is stable across releases and safe to
/// `switch` over. Human-readable guidance lives in `actionDetail`, never here.
///
/// - `none`: no signal
/// - `monitor`: log it, no human needed
/// - `flagForReview`: queue for a moderator
/// - `block`: withhold or limit the content
/// - `immediateIntervention`: crisis path
///
/// Decoding maps the spellings older API versions used (`no_action`,
/// `flag_for_moderator`) onto their current rungs. A value this SDK does not
/// recognise decodes as `flagForReview` rather than failing or vanishing, so
/// an unfamiliar verdict from a newer API still reaches a human.
public enum RecommendedAction: String, Codable, Sendable, CaseIterable, Comparable {
    case none
    case monitor
    case flagForReview = "flag_for_review"
    case block
    case immediateIntervention = "immediate_intervention"

    private var rank: Int {
        switch self {
        case .none: return 0
        case .monitor: return 1
        case .flagForReview: return 2
        case .block: return 3
        case .immediateIntervention: return 4
        }
    }

    public static func < (lhs: RecommendedAction, rhs: RecommendedAction) -> Bool {
        lhs.rank < rhs.rank
    }

    /// True for `flagForReview` and stronger: the verdict warrants a human looking at it.
    ///
    /// Branch on this rather than on `isBullying` / `unsafe` / a `.low` grooming
    /// risk, all of which fire on monitor-only cases and over-alert.
    public var isActionable: Bool {
        self >= .flagForReview
    }

    /// Normalise a raw API value, mapping legacy spellings. Returns `nil` for an unrecognised value.
    public init?(apiValue: String) {
        switch apiValue {
        case "no_action": self = .none
        case "flag_for_moderator": self = .flagForReview
        default: self.init(rawValue: apiValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecommendedAction(apiValue: raw) ?? .flagForReview
    }

    /// The strongest of the given actions (`nil`s skipped), or `.none` when there are none.
    public static func strongest(_ actions: [RecommendedAction?]) -> RecommendedAction {
        actions.compactMap { $0 }.max() ?? .none
    }
}

/// Direction of travel across a conversation, reported alongside `trajectoryRisk`.
///
/// `declining` is not the same as safe: `trajectoryRisk` stays anchored on the
/// worst turn seen and decays only slowly.
public enum ConversationTrajectory: String, Codable, Sendable {
    case rising
    case stable
    case declining
    case none
}

/// How prior conversation state was sourced on a continuation-aware endpoint.
public enum StateSource: String, Codable, Sendable {
    /// Decoded from a continuation token.
    case token
    /// No prior state.
    case fresh
    /// `resetConversation` forced a restart.
    case reset
}

/// Minimum severity at which a positive detection carries crisis-support resources.
/// Critical always does. The API default is `.high`.
public enum SupportThreshold: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

/// Analysis types available for voice/audio analysis.
public enum VoiceAnalysisType: String, Codable, Sendable {
    case bullying
    case unsafe
    case grooming
    case emotions
    case all
}

/// Analysis types available for image analysis.
public enum ImageAnalysisType: String, Codable, Sendable {
    case bullying
    case unsafe
    case emotions
    case all
}

/// Webhook event types for notification subscriptions.
public enum WebhookEventType: String, Codable, Sendable {
    case incidentCritical = "incident.critical"
    case incidentHigh = "incident.high"
    case groomingDetected = "grooming.detected"
    case selfHarmDetected = "self_harm.detected"
    case bullyingSevere = "bullying.severe"
}

/// Supported language codes for content analysis.
/// English is stable; all others are beta.
public enum Language: String, Codable, Sendable, CaseIterable {
    case en, es, pt, uk, sv, no, da, fi, de, fr
    case nl, pl, it, tr, ro, el, cs, hu, bg, hr, sk, lt, lv, et, sl, mt, ga
}

/// Language support maturity status.
public enum LanguageStatus: String, Codable, Sendable {
    case stable
    case beta
}

/// Detection endpoint identifiers for multi-endpoint analysis.
public enum Detection: String, Codable, Sendable {
    case bullying
    case grooming
    case unsafe
    case socialEngineering = "social-engineering"
    case appFraud = "app-fraud"
    case romanceScam = "romance-scam"
    case muleRecruitment = "mule-recruitment"
    case gamblingHarm = "gambling-harm"
    case coerciveControl = "coercive-control"
    case vulnerabilityExploitation = "vulnerability-exploitation"
    case radicalisation
}

/// Detection endpoint identifiers for document analysis.
public enum DocumentEndpointName: String, Codable, Sendable {
    case unsafe
    case bullying
    case grooming
    case socialEngineering = "social-engineering"
    case coerciveControl = "coercive-control"
    case radicalisation
    case romanceScam = "romance-scam"
    case muleRecruitment = "mule-recruitment"
}

/// Subscription tier levels.
public enum Tier: String, Codable, Sendable {
    case starter
    case indie
    case pro
    case business
    case enterprise
}

/// Verification mode for age/identity verification.
public enum VerificationMode: String, Codable, Sendable {
    case age
    case identity
}

/// Document types accepted for verification.
public enum DocumentType: String, Codable, Sendable {
    case passport
    case nationalId = "national_id"
    case driversLicense = "drivers_license"
}

/// Verification result status.
public enum VerificationStatus: String, Codable, Sendable {
    case verified
    case failed
    case needsReview = "needs_review"
}

/// Verification session status.
///
/// A session cancelled with ``Tuteliq/cancelVerificationSession(id:)`` reports `expired`.
public enum VerificationSessionStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    /// The user must supply (or re-supply) a document before the session can continue.
    case documentRequired = "document_required"
    case completed
    case failed
    case expired
    case cancelled
}

// MARK: - 2.x names

@available(*, deprecated, renamed: "flagForReview")
public extension RecommendedAction {
    /// The 2.x name of ``flagForReview``.
    static var flagForModerator: RecommendedAction {
        .flagForReview
    }
}

@available(*, deprecated, renamed: "nationalId")
public extension DocumentType {
    /// The 2.x name of ``nationalId``.
    static var idCard: DocumentType {
        .nationalId
    }
}
