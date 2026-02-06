import Foundation

/// Severity levels for detected content
public enum Severity: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

/// Grooming risk levels
public enum GroomingRisk: String, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case critical
}

/// Overall risk levels
public enum RiskLevel: String, Codable, Sendable {
    case safe
    case low
    case medium
    case high
    case critical
}

/// Emotion trend direction
public enum EmotionTrend: String, Codable, Sendable {
    case improving
    case stable
    case worsening
}

/// Target audience for action plans
public enum Audience: String, Codable, Sendable {
    case child
    case parent
    case educator
    case platform
}

/// Message role in conversations
public enum MessageRole: String, Codable, Sendable {
    case adult
    case child
    case unknown
}
