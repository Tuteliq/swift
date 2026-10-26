import Foundation

/// Errors returned by the Tuteliq SDK.
///
/// All API methods throw ``TuteliqError`` on failure. Use pattern matching
/// to handle specific error cases:
/// ```swift
/// do {
///     let result = try await tuteliq.detectBullying(content: text)
/// } catch let error as TuteliqError {
///     switch error {
///     case .rateLimitError:
///         // Back off and retry later
///     case .subscriptionError:
///         // Upgrade plan or check tier access
///     default:
///         print(error.localizedDescription)
///     }
/// }
/// ```
public enum TuteliqError: Error, LocalizedError, Sendable {
    /// API key is missing or invalid (HTTP 401).
    case authenticationError(String)

    /// Per-minute rate limit exceeded (HTTP 429). Retried automatically with backoff.
    case rateLimitError(String)

    /// Monthly quota exhausted (HTTP 429 with `RATE_2003` / `QUOTA_EXCEEDED`).
    /// Not retried: it will not clear until the quota resets or credits are added.
    case quotaExceededError(String)

    /// Invalid request parameters (HTTP 400).
    case validationError(String, details: AnyCodable? = nil)

    /// Resource not found (HTTP 404).
    case notFoundError(String)

    /// Subscription or tier restriction (HTTP 403).
    ///
    /// Thrown when the current plan does not include access to the requested
    /// endpoint or when the subscription is inactive/expired.
    case subscriptionError(String, code: String? = nil)

    /// Server error (HTTP 5xx).
    case serverError(String, statusCode: Int)

    /// Request timed out.
    case timeoutError(String)

    /// Network connectivity issue.
    case networkError(String)

    /// Unknown or unexpected error.
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case let .authenticationError(msg): return "Authentication Error: \(msg)"
        case let .rateLimitError(msg): return "Rate Limit Error: \(msg)"
        case let .quotaExceededError(msg): return "Quota Exceeded: \(msg)"
        case let .validationError(msg, _): return "Validation Error: \(msg)"
        case let .notFoundError(msg): return "Not Found: \(msg)"
        case let .subscriptionError(msg, _): return "Subscription Error: \(msg)"
        case let .serverError(msg, code): return "Server Error (\(code)): \(msg)"
        case let .timeoutError(msg): return "Timeout: \(msg)"
        case let .networkError(msg): return "Network Error: \(msg)"
        case let .unknownError(msg): return "Error: \(msg)"
        }
    }
}

/// API error response structure (internal).
struct APIErrorResponse: Codable {
    let error: APIError

    struct APIError: Codable {
        let code: String
        let message: String
        let details: AnyCodable?
        let suggestion: String?
        let links: ErrorLinks?
    }

    struct ErrorLinks: Codable {
        let upgrade: String?
        let docs: String?
        let dashboard: String?
    }
}
