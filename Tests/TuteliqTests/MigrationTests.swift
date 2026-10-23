@testable import Tuteliq
import XCTest

/// 3.0.0 renamed some public API. The old names stay as deprecated aliases so
/// an app moving from 2.x still compiles, with a warning naming the new one.
@available(*, deprecated)
extension TuteliqTests {
    func testFlagForModeratorStillNamesTheReviewAction() {
        XCTAssertEqual(RecommendedAction.flagForModerator, .flagForReview)
        switch RecommendedAction.flagForReview {
        case .flagForModerator: break
        default: XCTFail("a 2.x switch on flagForModerator must still match")
        }
    }

    func testIdCardStillNamesTheNationalId() {
        XCTAssertEqual(DocumentType.idCard, .nationalId)
    }

    func testUpdatePolicyStillSetsThePolicy() async throws {
        var seen: URLRequest?
        let client = try makeClient { request in
            seen = request
            return self.mockResponse(json: ["success": true, "config": ["a": 1]])
        }
        _ = try await client.updatePolicy(["a": AnyCodable(1)])
        XCTAssertEqual(seen?.url?.path, "/api/v1/policy")
        XCTAssertEqual(seen?.httpMethod, "PUT")
    }
}

/// A session ID is one path segment: encoded once, and never able to leave it.
extension TuteliqTests {
    private func sessionPath(_ id: String) async throws -> String? {
        var seen: URLRequest?
        let client = try makeClient { request in
            seen = request
            return self.mockResponse(json: ["ok": true])
        }
        _ = try? await client.cancelVerificationSession(id: id)
        return seen?.url?.absoluteString
    }

    func testSessionIdIsEncodedOnce() async throws {
        let url = try await sessionPath("a b")
        XCTAssertEqual(url, "https://api.tuteliq.ai/api/v1/verify/session/a%20b")
    }

    func testSessionIdCannotAddPathSegments() async throws {
        let url = try await sessionPath("a/../../x")
        XCTAssertEqual(url, "https://api.tuteliq.ai/api/v1/verify/session/a%2F..%2F..%2Fx")
    }

    func testDotSegmentsAreRejected() async throws {
        let client = try makeClient { _ in
            XCTFail("no request may be sent for a dot segment")
            return self.mockResponse(json: ["ok": true])
        }
        for id in [".", ".."] {
            do {
                _ = try await client.getVerificationSession(id: id)
                XCTFail("\(id) was accepted")
            } catch TuteliqError.validationError {}
        }
    }

    /// Epoch milliseconds do not fit in a 32-bit `Int` (arm64_32 watchOS).
    func testLivenessChallengeExpiryIsSixtyFourBit() throws {
        let json = #"{"nonce":"n","signature":"s","expires_at":1715000300000,"challenges":["center"]}"#
        let challenge = try JSONDecoder().decode(LivenessChallenge.self, from: Data(json.utf8))
        let expiresAt: Int64 = challenge.expiresAt
        XCTAssertEqual(expiresAt, 1_715_000_300_000)
    }
}
