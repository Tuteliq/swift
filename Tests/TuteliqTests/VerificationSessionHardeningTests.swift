@testable import Tuteliq
import XCTest

// MARK: - Session links

/// A session link usually reaches the app through a deep or universal link, so
/// its contents are not trusted: it must never decide where the device uploads
/// document images, chip data, the selfie and the session token.
final class SessionLinkTests: XCTestCase {
    private func rejects(_ link: String, apiBaseURL: URL? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try VerificationSessionCredentials(sessionURL: link, apiBaseURL: apiBaseURL), link, file: file, line: line)
    }

    func testRejectsCleartextLinks() {
        rejects("http://verify.tuteliq.ai/age/?session=s1&token=t1")
    }

    func testRejectsCustomSchemes() {
        rejects("myapp://verify.tuteliq.ai/age/?session=s1&token=t1")
    }

    func testRejectsLinksWithCredentials() {
        rejects("https://user:pass@verify.tuteliq.ai/age/?session=s1&token=t1")
        rejects("https://user@verify.tuteliq.ai/age/?session=s1&token=t1")
    }

    func testRejectsForeignHosts() {
        rejects("https://evil.example/age/?session=s1&token=t1")
        rejects("https://verify.tuteliq.ai.evil.example/age/?session=s1&token=t1")
    }

    func testRejectsSessionIdsThatAreNotOneSegment() {
        rejects("https://verify.tuteliq.ai/age/?session=a%2F..%2F..%2Fx&token=t1")
        rejects("https://verify.tuteliq.ai/age/?session=a%20b&token=t1")
        rejects("https://verify.tuteliq.ai/age/?session=..&token=t1")
    }

    func testUploadsGoToTheAPIWhateverHostTheLinkWasOn() throws {
        let credentials = try VerificationSessionCredentials(sessionURL: "https://verify.tuteliq.ai/age/?session=s1&token=t1")
        XCTAssertEqual(credentials.apiBaseURL.absoluteString, "https://api.tuteliq.ai")
    }

    func testAnExplicitOverrideAcceptsItsOwnLinks() throws {
        let api = try XCTUnwrap(URL(string: "https://api.staging.example"))
        let credentials = try VerificationSessionCredentials(sessionURL: "https://verify.staging.example/age/?session=s1&token=t1", apiBaseURL: api)
        XCTAssertEqual(credentials.apiBaseURL, api)
        // The override is the app's own configuration; the link still has to be https without credentials.
        rejects("http://verify.staging.example/age/?session=s1&token=t1", apiBaseURL: api)
        rejects("https://u:p@verify.staging.example/age/?session=s1&token=t1", apiBaseURL: api)
    }

    func testAnOverrideMustBeHTTPSExceptOnThisMachine() throws {
        try rejects("https://verify.tuteliq.ai/age/?session=s1&token=t1", apiBaseURL: XCTUnwrap(URL(string: "http://api.staging.example")))
        let local = try VerificationSessionCredentials(
            sessionURL: "http://localhost:8080/age/?session=s1&token=t1", apiBaseURL: XCTUnwrap(URL(string: "http://localhost:8080"))
        )
        XCTAssertEqual(local.apiBaseURL.absoluteString, "http://localhost:8080")
    }

    func testABadLinkErrorDoesNotRepeatTheLink() {
        let link = "https://evil.example/age/?session=s1&token=secret-token-123"
        XCTAssertThrowsError(try VerificationSessionCredentials(sessionURL: link)) { error in
            let text = "\(error) \(error.localizedDescription) \(String(reflecting: error))"
            XCTAssertFalse(text.contains("secret-token-123"), text)
        }
    }
}

// MARK: - Redaction

/// The session token is a bearer credential. Printing, dumping or interpolating
/// anything that holds it must not show it.
final class TokenRedactionTests: XCTestCase {
    private let token = "secret-token-123"

    private func shown(_ value: Any) -> String {
        var dumped = ""
        dump(value, to: &dumped)
        return "\(value) \(String(describing: value)) \(String(reflecting: value)) \(dumped)"
    }

    func testCredentialsNeverShowTheToken() throws {
        let credentials = try VerificationSessionCredentials(sessionURL: "https://verify.tuteliq.ai/age/?session=s1&token=\(token)")
        let text = shown(credentials)
        XCTAssertFalse(text.contains(token), text)
        XCTAssertTrue(text.contains("s1"), "the session ID is not a secret and helps debugging")
    }

    func testTheClientNeverShowsTheToken() throws {
        let credentials = try VerificationSessionCredentials(sessionURL: "https://verify.tuteliq.ai/age/?session=s1&token=\(token)")
        let text = shown(VerificationSessionClient(credentials: credentials))
        XCTAssertFalse(text.contains(token), text)
    }

    func testALivenessCaptureNeverShowsItsToken() {
        let capture = LivenessCapture(token: #"{"signature":"\#(token)"}"#, frames: [Data("f".utf8)], nonce: "n")
        let text = shown(capture)
        XCTAssertFalse(text.contains(token), text)
    }
}

// MARK: - Liveness timing

private func challenge(expiresIn seconds: TimeInterval = 300) -> LivenessChallenge {
    LivenessChallenge(
        nonce: "n", signature: "sig",
        expiresAt: Int64(Date().addingTimeInterval(seconds).timeIntervalSince1970 * 1000),
        challenges: ["center", "left"]
    )
}

final class LivenessTimingTests: XCTestCase {
    func testACompletionInTheFutureIsRejected() {
        var token = LivenessTokenBuilder(challenge: challenge(), createdAt: Date().addingTimeInterval(-5))
        XCTAssertThrowsError(try token.complete("center", at: Date().addingTimeInterval(30)))
    }

    func testAnExpiredTokenIsNotEncoded() throws {
        let start = Date().addingTimeInterval(-400)
        var token = LivenessTokenBuilder(challenge: challenge(expiresIn: -10), createdAt: start)
        try token.complete("center", at: start.addingTimeInterval(1))
        try token.complete("left", at: start.addingTimeInterval(2))
        XCTAssertTrue(token.isExpired(at: Date()))
        XCTAssertThrowsError(try token.encoded())
    }

    func testEarliestNextCompletionIsTheMinimumIntervalAfterTheLastStep() throws {
        let start = Date().addingTimeInterval(-10)
        var token = LivenessTokenBuilder(challenge: challenge(), createdAt: start)
        XCTAssertEqual(token.earliestNextCompletion.timeIntervalSince(start), LivenessTokenBuilder.minimumStepInterval, accuracy: 0.002)
        let passed = start.addingTimeInterval(2)
        try token.complete("center", at: passed)
        XCTAssertEqual(token.earliestNextCompletion.timeIntervalSince(passed), LivenessTokenBuilder.minimumStepInterval, accuracy: 0.002)
        XCTAssertFalse(token.isExpired(at: Date()))
    }

    /// A phone a few seconds fast must not fail a real user: timestamps are
    /// sent on the server's clock when the offset is known.
    func testTimestampsAreSentOnTheServersClock() throws {
        let start = Date().addingTimeInterval(-10)
        var token = LivenessTokenBuilder(challenge: challenge(), createdAt: start, clockOffset: -7)
        try token.complete("center", at: start.addingTimeInterval(1))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(token.withAllCompleted(after: start.addingTimeInterval(2)).encoded().utf8)) as? [String: Any])
        XCTAssertEqual(payload["createdAt"] as? Int64, LivenessTokenBuilder.milliseconds(start.addingTimeInterval(-7)))
        let steps = try XCTUnwrap(payload["challenges"] as? [[String: Any]])
        XCTAssertEqual(steps[0]["completedAt"] as? Int64, LivenessTokenBuilder.milliseconds(start.addingTimeInterval(-6)))
    }
}

private extension LivenessTokenBuilder {
    func withAllCompleted(after date: Date) throws -> LivenessTokenBuilder {
        var copy = self
        var at = date
        while let next = copy.nextChallenge {
            try copy.complete(next, at: at)
            at = at.addingTimeInterval(1)
        }
        return copy
    }
}

// MARK: - Session client

final class SessionClientCoverageTests: XCTestCase {
    private func client(link: String = "https://verify.tuteliq.ai/age/?session=s1&token=t1", apiBaseURL: URL? = nil) throws -> VerificationSessionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionMockURLProtocol.self]
        let credentials = try VerificationSessionCredentials(sessionURL: link, apiBaseURL: apiBaseURL)
        return VerificationSessionClient(credentials: credentials, session: URLSession(configuration: config))
    }

    override func tearDown() {
        SessionMockURLProtocol.headers = [:]
        super.tearDown()
    }

    func testTheOverrideIsWhereRequestsGo() async throws {
        var url: URL?
        SessionMockURLProtocol.handler = { request, _ in url = request.url; return (200, Data(#"{"verification_mode":"full"}"#.utf8)) }
        let mode = try await client(link: "https://verify.staging.example/age/?session=s1&token=t1", apiBaseURL: XCTUnwrap(URL(string: "https://api.staging.example"))).fetchMode()
        XCTAssertEqual(url?.absoluteString, "https://api.staging.example/api/v1/verify/session/s1/mode")
        XCTAssertEqual(mode.verificationMode, .full)
    }

    func testASessionIdIsEncodedOnceAndStaysOneSegment() async {
        var urls: [String] = []
        SessionMockURLProtocol.handler = { request, _ in urls.append(request.url!.absoluteString); return (200, Data()) }
        for id in ["a b", "a/../../x"] {
            let credentials = VerificationSessionCredentials(sessionId: id, token: "t", mode: .age)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [SessionMockURLProtocol.self]
            await VerificationSessionClient(credentials: credentials, session: URLSession(configuration: config)).reportProgress(.connected)
        }
        XCTAssertEqual(urls, [
            "https://api.tuteliq.ai/api/v1/verify/session/a%20b/progress",
            "https://api.tuteliq.ai/api/v1/verify/session/a%2F%2E%2E%2F%2E%2E%2Fx/progress",
        ])
    }

    func testReportProgressSendsTheStep() async throws {
        var sent: (URLRequest, Data)?
        SessionMockURLProtocol.handler = { request, body in sent = (request, body); return (200, Data()) }
        try await client().reportProgress(.connected)
        let (request, body) = try XCTUnwrap(sent)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/verify/session/s1/progress")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["step": VerificationProgressStep.connected.rawValue])
    }

    func testStartLivenessFetchesTheChallengeAndTheServersClock() async throws {
        let serverNow = Date().addingTimeInterval(-30)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        SessionMockURLProtocol.headers = ["Date": formatter.string(from: serverNow)]
        var path: String?
        SessionMockURLProtocol.handler = { request, _ in
            path = request.url?.path
            return (200, Data(#"{"nonce":"n","signature":"s","expires_at":9999999999999,"challenges":["center"]}"#.utf8))
        }
        let token = try await client().startLiveness()
        XCTAssertEqual(path, "/api/v1/verify/age/challenge")
        XCTAssertEqual(token.challenge.nonce, "n")
        XCTAssertEqual(token.clockOffset, -30, accuracy: 2)
    }

    func testValidateChipThrowsForAMissingSession() async throws {
        SessionMockURLProtocol.handler = { _, _ in (404, Data(#"{"error":{"code":"VERIFY_11006","message":"Session not found"}}"#.utf8)) }
        do {
            _ = try await client().validateChip([.dg1: Data([0x61])], documentType: .passport)
            XCTFail("Expected sessionNotFound")
        } catch {
            XCTAssertEqual(error as? VerificationError, .sessionNotFound)
        }
    }

    /// A misconfigured base URL or a proxy answers 404 too; only the API's own
    /// route-not-found means chip validation is not offered.
    func testValidateChipThrowsForAnyOther404() async throws {
        for (body, code) in [(#"{"error":{"code":"OTHER","message":"x"}}"#, "OTHER"), ("<html>Not Found</html>", nil)] {
            SessionMockURLProtocol.handler = { _, _ in (404, Data(body.utf8)) }
            do {
                _ = try await client().validateChip([.dg1: Data([0x61])], documentType: .passport)
                XCTFail("Expected an error for \(body)")
            } catch let VerificationError.server(actualCode, _, statusCode) {
                XCTAssertEqual(actualCode, code, body)
                XCTAssertEqual(statusCode, 404, body)
            } catch {
                XCTFail("Expected a 404 server error for \(body), got \(error)")
            }
        }
    }

    func testSubmitSendsTheBackAndTwoTiltFrames() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"ok":true,"status":"completed"}"#.utf8)) }
        _ = try await client().submit(SessionSubmission(
            documentType: .nationalId, documentFront: Data("F".utf8), documentBack: Data("B".utf8),
            tiltFrames: [Data("T1".utf8), Data("T2".utf8), Data("T3".utf8)]
        ))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"id_back\"; filename=\"id_back.jpg\""))
        XCTAssertTrue(text.contains("name=\"tilt_frame_1\""))
        XCTAssertTrue(text.contains("name=\"tilt_frame_2\""))
        XCTAssertFalse(text.contains("name=\"tilt_frame_3\""))
        XCTAssertFalse(text.contains("name=\"passport\""))
    }

    /// Raw facial measurements stay on the device; the derived verdict and pass rates are sent.
    func testCaptureContextSendsNoRawFacialMeasurements() throws {
        let depth = LivenessDepthEvidence(
            sensor: "truedepth", verdict: .live, framesAnalyzed: 10, framesWithDepth: 9, reliefPassRate: 0.9, sizePassRate: 1,
            noseReliefMM: 18.5, interpupillaryMM: 61.2, distanceCM: 32, coverage: 0.8
        )
        let context = CaptureContext(
            sdk: .init(name: "x", version: "1", platform: "ios", osVersion: "26.0", deviceModel: "iPhone17,1"),
            pipeline: "native-ios", pipelineVersion: 1,
            face: .init(camera: "truedepth", livenessEngine: "e", livenessEngineVersion: 1, depth: depth)
        )
        let json = try XCTUnwrap(context.encodedJSON())
        for raw in ["nose_relief", "interpupillary", "distance_cm", "18.5", "61.2"] {
            XCTAssertFalse(json.contains(raw), raw)
        }
        XCTAssertTrue(json.contains("\"relief_pass_rate\":0.9"))
        XCTAssertTrue(json.contains("\"verdict\":\"live\""))
        // Still available on the device, e.g. for a debug overlay.
        XCTAssertEqual(depth.interpupillaryMM, 61.2)
    }
}
