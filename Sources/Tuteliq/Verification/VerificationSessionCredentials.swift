import Foundation

/// What the capture device needs to drive a verification session.
///
/// A session is created server-side with an API key
/// (``Tuteliq/Tuteliq/createVerificationSession(_:)``); its `url` carries the
/// session ID and a session-scoped token. The device only ever uses that
/// token, never your API key.
public struct VerificationSessionCredentials: Sendable, Equatable {
    public let sessionId: String
    /// Session-scoped bearer token. Treat it as a secret.
    public let token: String
    public let mode: VerificationMode
    /// Origin serving the session endpoints. ``defaultAPIBaseURL`` unless the app overrides it.
    public let apiBaseURL: URL
    /// Company name to show in the UI, when the session URL carries one.
    public let companyName: String?
    /// Where the hosted flow would send the user afterwards (`https` only).
    public let redirectURL: URL?

    public init(
        sessionId: String,
        token: String,
        mode: VerificationMode,
        apiBaseURL: URL = URL(string: "https://api.tuteliq.ai")!,
        companyName: String? = nil,
        redirectURL: URL? = nil
    ) {
        self.sessionId = sessionId
        self.token = token
        self.mode = mode
        self.apiBaseURL = apiBaseURL
        self.companyName = companyName
        self.redirectURL = redirectURL
    }

    /// Where uploads go when the app sets no override.
    public static let defaultAPIBaseURL = URL(string: "https://api.tuteliq.ai")!
    /// The hosts Tuteliq issues session links on.
    public static let sessionLinkHosts: Set<String> = ["verify.tuteliq.ai"]

    /// Parses a session URL (``Tuteliq/VerificationSession/url``), e.g.
    /// `https://verify.tuteliq.ai/age/?session=…&token=…`.
    ///
    /// A link usually reaches the app from outside it (a deep or universal link),
    /// so it never decides where the device uploads. Uploads go to
    /// ``defaultAPIBaseURL`` unless the app passes `apiBaseURL` itself. The link
    /// must be `https`, carry no user name or password, and, without an override,
    /// be on one of ``sessionLinkHosts``.
    ///
    /// - Parameter apiBaseURL: Your own API origin, e.g. a staging deployment.
    ///   Must be `https`, or `http` on `localhost`. With an override, links on
    ///   other hosts are accepted.
    public init(sessionURL: URL, apiBaseURL: URL? = nil) throws {
        if let apiBaseURL, !Self.isAllowedOrigin(apiBaseURL) {
            throw VerificationError.invalidSessionURL("The API base URL must use https")
        }
        guard let components = URLComponents(url: sessionURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased()
        else { throw VerificationError.invalidSessionURL("Not an absolute URL") }
        guard components.user == nil, components.password == nil else {
            throw VerificationError.invalidSessionURL("The link must not carry a user name or password")
        }
        let localOverride = apiBaseURL.map { $0.scheme == "http" && Self.isLocal(host: $0.host) && Self.isLocal(host: host) } ?? false
        guard scheme == "https" || (scheme == "http" && localOverride) else {
            throw VerificationError.invalidSessionURL("The link must use https")
        }
        guard apiBaseURL != nil || Self.sessionLinkHosts.contains(host) else {
            throw VerificationError.invalidSessionURL("The link is not a Tuteliq verification link")
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let session = value("session"), let token = value("token") else {
            throw VerificationError.invalidSessionURL("Missing session or token parameter")
        }
        guard Self.isSessionId(session) else {
            throw VerificationError.invalidSessionURL("The session ID is not valid")
        }

        let firstSegment = components.path.split(separator: "/").first.map(String.init)
        let mode: VerificationMode = firstSegment == "identity" ? .identity : .age

        let redirect = value("redirect").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }

        self.init(
            sessionId: session,
            token: token,
            mode: mode,
            apiBaseURL: apiBaseURL ?? Self.defaultAPIBaseURL,
            companyName: value("company"),
            redirectURL: redirect
        )
    }

    /// Parses a session URL string.
    public init(sessionURL: String, apiBaseURL: URL? = nil) throws {
        // The error never repeats the link: it carries the session token.
        guard let url = URL(string: sessionURL) else { throw VerificationError.invalidSessionURL("Not a URL") }
        try self.init(sessionURL: url, apiBaseURL: apiBaseURL)
    }

    /// Letters, digits, `-` and `_`: one path segment as it is, with nothing to encode.
    static func isSessionId(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" || $0 == "_"
        }
    }

    static func isLocal(host: String?) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host?.lowercased() ?? "")
    }

    static func isAllowedOrigin(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.host != nil else { return false }
        return url.scheme == "https" || (url.scheme == "http" && isLocal(host: url.host))
    }
}

/// The token is a bearer credential: nothing that prints or dumps the credentials shows it.
extension VerificationSessionCredentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "VerificationSessionCredentials(sessionId: \(sessionId), mode: \(mode), apiBaseURL: \(apiBaseURL.absoluteString), token: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["sessionId": sessionId, "mode": mode, "apiBaseURL": apiBaseURL, "token": "<redacted>"], displayStyle: .struct)
    }
}

public extension Tuteliq {
    /// Creates a verification session and returns the credentials a capture device needs.
    ///
    /// Call this where your API key lives. If that's your backend, create the
    /// session there and pass `session.url` to the app instead; the app then
    /// uses ``VerificationSessionCredentials/init(sessionURL:apiBaseURL:)``.
    func createVerificationCredentials(
        _ input: CreateVerificationSessionInput
    ) async throws -> VerificationSessionCredentials {
        let session = try await createVerificationSession(input)
        // The session belongs to the API this client talks to.
        return try VerificationSessionCredentials(sessionURL: session.url, apiBaseURL: baseURL == VerificationSessionCredentials.defaultAPIBaseURL ? nil : baseURL)
    }
}
