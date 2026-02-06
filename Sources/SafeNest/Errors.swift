import Foundation

/// SafeNest SDK errors
public enum SafeNestError: Error, LocalizedError, Sendable {
    /// API key is missing or invalid
    case authenticationError(String)

    /// Rate limit exceeded
    case rateLimitError(String)

    /// Invalid request parameters
    case validationError(String, details: Any? = nil)

    /// Resource not found
    case notFoundError(String)

    /// Server error (5xx)
    case serverError(String, statusCode: Int)

    /// Request timed out
    case timeoutError(String)

    /// Network connectivity issue
    case networkError(String)

    /// Unknown error
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .rateLimitError(let message):
            return "Rate Limit Error: \(message)"
        case .validationError(let message, _):
            return "Validation Error: \(message)"
        case .notFoundError(let message):
            return "Not Found: \(message)"
        case .serverError(let message, let code):
            return "Server Error (\(code)): \(message)"
        case .timeoutError(let message):
            return "Timeout: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .unknownError(let message):
            return "Error: \(message)"
        }
    }
}

/// API error response structure
struct APIErrorResponse: Codable {
    let error: APIError

    struct APIError: Codable {
        let code: String
        let message: String
        let details: AnyCodable?
    }
}
