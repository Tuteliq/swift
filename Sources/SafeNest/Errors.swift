import Foundation

/// Errors returned by the SafeNest SDK.
///
/// All API methods throw ``SafeNestError`` on failure. Use pattern matching
/// to handle specific error cases:
/// ```swift
/// do {
///     let result = try await safenest.detectBullying(content: text)
/// } catch let error as SafeNestError {
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
public enum SafeNestError: Error, LocalizedError, Sendable {
    /// API key is missing or invalid (HTTP 401).
    case authenticationError(String)

    /// Rate limit exceeded (HTTP 429).
    case rateLimitError(String)

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
        case .authenticationError(let msg): return "Authentication Error: \(msg)"
        case .rateLimitError(let msg): return "Rate Limit Error: \(msg)"
        case .validationError(let msg, _): return "Validation Error: \(msg)"
        case .notFoundError(let msg): return "Not Found: \(msg)"
        case .subscriptionError(let msg, _): return "Subscription Error: \(msg)"
        case .serverError(let msg, let code): return "Server Error (\(code)): \(msg)"
        case .timeoutError(let msg): return "Timeout: \(msg)"
        case .networkError(let msg): return "Network Error: \(msg)"
        case .unknownError(let msg): return "Error: \(msg)"
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
