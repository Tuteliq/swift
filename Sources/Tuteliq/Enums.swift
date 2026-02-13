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

/// Recommended actions after analysis.
public enum RecommendedAction: String, Codable, Sendable {
    case none
    case monitor
    case flagForModerator = "flag_for_moderator"
    case immediateIntervention = "immediate_intervention"
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
