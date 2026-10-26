import Foundation

/// Errors from a native verification session.
public enum VerificationError: Error, LocalizedError, Sendable, Equatable {
    /// The session URL is missing its session ID or token.
    case invalidSessionURL(String)
    /// The session doesn't exist (`VERIFY_11006`).
    case sessionNotFound
    /// The session expired or was cancelled (`VERIFY_11007`).
    case sessionExpired
    /// The session token was rejected (`VERIFY_11008`).
    case invalidSessionToken
    /// The session was already submitted (`VERIFY_11009`).
    case sessionAlreadyCompleted
    /// The session can't accept this request in its current state (`VERIFY_11010`).
    case sessionWrongState
    /// Too many attempts; retry after the given delay.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other API error.
    case server(code: String?, message: String, statusCode: Int)
    case network(String)
    case timeout
    /// The response could not be decoded.
    case invalidResponse(String)
    case cameraUnavailable
    case cameraPermissionDenied
    /// Liveness could not be completed (challenges timed out twice, or the token expired).
    case livenessFailed(String)
    /// The user cancelled the flow.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .invalidSessionURL(detail): return "Invalid verification link: \(detail)"
        case .sessionNotFound: return "This verification session doesn't exist."
        case .sessionExpired: return "This verification session has expired or was cancelled."
        case .invalidSessionToken: return "This verification link is not valid."
        case .sessionAlreadyCompleted: return "This verification has already been submitted."
        case .sessionWrongState: return "This verification can't continue from its current state."
        case let .rateLimited(retryAfter):
            // Public case: any value can arrive here, and `Int(_:)` traps on infinity and NaN.
            guard let retryAfter, retryAfter.isFinite, retryAfter >= 0 else { return "Too many attempts. Try again shortly." }
            return "Too many attempts. Try again in \(Int(min(retryAfter, 86400).rounded(.up))) seconds."
        case let .server(_, message, _): return message
        case let .network(message): return "Network error: \(message)"
        case .timeout: return "The request timed out."
        case let .invalidResponse(detail): return "Unexpected response: \(detail)"
        case .cameraUnavailable: return "The camera is not available."
        case .cameraPermissionDenied: return "Camera access is needed to verify your identity. Enable it in Settings."
        case let .livenessFailed(reason): return reason
        case .cancelled: return "Verification was cancelled."
        }
    }

    /// API error code, when the error came from the API.
    public var code: String? {
        switch self {
        case .sessionNotFound: return "VERIFY_11006"
        case .sessionExpired: return "VERIFY_11007"
        case .invalidSessionToken: return "VERIFY_11008"
        case .sessionAlreadyCompleted: return "VERIFY_11009"
        case .sessionWrongState: return "VERIFY_11010"
        case let .server(code, _, _): return code
        default: return nil
        }
    }
}
