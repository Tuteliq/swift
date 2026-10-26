import Foundation

/// Builds the `liveness_token` the server validates against its signed challenge.
///
/// The server checks: `id` is a UUID v4; exactly the challenges it issued, in
/// its order; `completedAt` strictly increasing and at least 500 ms after
/// `createdAt` and after each other; every timestamp within `[createdAt, now]`
/// on its clock; the whole thing used within 5 minutes; `createdAt` no earlier
/// than the challenge's issue time.
///
/// The builder enforces the order, the interval, no timestamp in the future and
/// the age. Timestamps are sent on the server's clock when ``clockOffset`` is
/// known, which ``VerificationSessionClient/startLiveness()`` sets; creating the
/// builder after the challenge was fetched keeps `createdAt` after its issue time.
public struct LivenessTokenBuilder: Sendable, Equatable {
    /// Gap enforced between steps. The server requires 500 ms; the margin absorbs clock rounding.
    public static let minimumStepInterval: TimeInterval = 0.55
    /// The server accepts tokens up to 300 s old; stop well before.
    public static let maximumAge: TimeInterval = 280

    public let challenge: LivenessChallenge
    /// Server clock minus device clock, in seconds. Added to every timestamp sent.
    public let clockOffset: TimeInterval
    public let id: String
    /// Epoch milliseconds.
    public let createdAt: Int64
    public private(set) var completions: [Completion] = []

    public struct Completion: Sendable, Equatable {
        public let type: String
        /// Epoch milliseconds.
        public let completedAt: Int64
    }

    /// - Parameters:
    ///   - createdAt: When the liveness capture started, on the device's clock.
    ///   - clockOffset: Server clock minus device clock, when known.
    public init(challenge: LivenessChallenge, createdAt: Date, clockOffset: TimeInterval = 0, id: UUID = UUID()) {
        self.challenge = challenge
        self.clockOffset = clockOffset
        self.id = id.uuidString.lowercased()
        self.createdAt = Self.milliseconds(createdAt.addingTimeInterval(clockOffset))
    }

    /// The challenge to run next, or `nil` when all are done.
    public var nextChallenge: String? {
        completions.count < challenge.challenges.count ? challenge.challenges[completions.count] : nil
    }

    public var isComplete: Bool {
        nextChallenge == nil
    }

    /// The earliest moment, on the device's clock, the next completion may be
    /// recorded. Wait until then before accepting the next prompt: recording a
    /// completion later than it happened works against the server's checks.
    public var earliestNextCompletion: Date {
        let last = completions.last?.completedAt ?? createdAt
        return Date(timeIntervalSince1970: TimeInterval(last) / 1000 + Self.minimumStepInterval - clockOffset)
    }

    /// Records that the next challenge passed at `date` (device clock). A date in
    /// the future is refused: it would put a timestamp after the server's "now".
    public mutating func complete(_ type: String, at date: Date, now: Date = Date()) throws {
        guard type == nextChallenge else {
            throw VerificationError.livenessFailed("Challenge \(type) completed out of order")
        }
        guard date <= now.addingTimeInterval(Self.futureTolerance) else {
            throw VerificationError.livenessFailed("Challenge \(type) completed in the future")
        }
        guard date >= earliestNextCompletion else {
            throw VerificationError.livenessFailed("Challenge \(type) completed too soon after the previous step")
        }
        completions.append(Completion(type: type, completedAt: Self.milliseconds(date.addingTimeInterval(clockOffset))))
    }

    /// Clock rounding allowed when checking that a completion is not in the future.
    static let futureTolerance: TimeInterval = 0.25

    /// Whether the token (or its challenge) is too old to be accepted at `date` (device clock).
    public func isExpired(at date: Date) -> Bool {
        let now = Self.milliseconds(date.addingTimeInterval(clockOffset))
        return now - createdAt > Int64(Self.maximumAge * 1000) || now > challenge.expiresAt
    }

    /// The JSON string sent as `liveness_token`. Refused once the token or its challenge has expired.
    public func encoded(at date: Date = Date()) throws -> String {
        guard isComplete else { throw VerificationError.livenessFailed("Liveness sequence incomplete") }
        guard !isExpired(at: date) else { throw VerificationError.livenessFailed("The liveness challenge expired. Start again.") }
        let payload: [String: Any] = [
            "id": id,
            "createdAt": createdAt,
            "nonce": challenge.nonce,
            "nonceExpiresAt": challenge.expiresAt,
            "signature": challenge.signature,
            "challenges": completions.map { ["type": $0.type, "passed": true, "completedAt": $0.completedAt] },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
