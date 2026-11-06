@testable import Tuteliq
import XCTest

// MARK: - Credentials

final class CredentialsTests: XCTestCase {
    func testParsesHostedSessionURL() throws {
        let credentials = try VerificationSessionCredentials(
            sessionURL: "https://verify.tuteliq.ai/identity/?session=abc123&token=tok456&company=Acme%20Inc&redirect=https%3A%2F%2Facme.com%2Fdone"
        )
        XCTAssertEqual(credentials.sessionId, "abc123")
        XCTAssertEqual(credentials.token, "tok456")
        XCTAssertEqual(credentials.mode, .identity)
        // Uploads go to the API, whatever host the link was on.
        XCTAssertEqual(credentials.apiBaseURL.absoluteString, "https://api.tuteliq.ai")
        XCTAssertEqual(credentials.companyName, "Acme Inc")
        XCTAssertEqual(credentials.redirectURL?.absoluteString, "https://acme.com/done")
    }

    func testRejectsURLWithoutToken() {
        XCTAssertThrowsError(try VerificationSessionCredentials(sessionURL: "https://verify.tuteliq.ai/age/?session=abc"))
    }

    func testIgnoresNonHTTPSRedirect() throws {
        let credentials = try VerificationSessionCredentials(
            sessionURL: "https://verify.tuteliq.ai/age/?session=a&token=b&redirect=http%3A%2F%2Fevil.com"
        )
        XCTAssertEqual(credentials.mode, .age)
        XCTAssertNil(credentials.redirectURL)
    }
}

// MARK: - Liveness token

private func makeChallenge(_ types: [String] = ["center", "left", "right", "blink", "smile"]) -> LivenessChallenge {
    LivenessChallenge(nonce: "nonce-1", signature: "sig", expiresAt: Int64(Date().addingTimeInterval(300).timeIntervalSince1970 * 1000), challenges: types)
}

final class LivenessTokenTests: XCTestCase {
    func testEncodesServerShape() throws {
        // In the past: a completion may not be recorded in the future.
        let start = Date().addingTimeInterval(-10)
        var builder = LivenessTokenBuilder(challenge: makeChallenge(["center", "blink"]), createdAt: start)
        try builder.complete("center", at: start.addingTimeInterval(1))
        try builder.complete("blink", at: start.addingTimeInterval(2))

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(builder.encoded().utf8)) as? [String: Any])
        let id = try XCTUnwrap(json["id"] as? String)
        XCTAssertNotNil(id.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression))
        XCTAssertEqual(json["nonce"] as? String, "nonce-1")
        XCTAssertEqual(json["signature"] as? String, "sig")
        XCTAssertNotNil(json["nonceExpiresAt"] as? Int)
        let challenges = try XCTUnwrap(json["challenges"] as? [[String: Any]])
        XCTAssertEqual(challenges.map { $0["type"] as? String }, ["center", "blink"])
        XCTAssertEqual(challenges.map { $0["passed"] as? Bool }, [true, true])
        let times = challenges.compactMap { $0["completedAt"] as? Int64 }
        XCTAssertEqual(times.count, 2)
        XCTAssertGreaterThanOrEqual(try times[0] - XCTUnwrap(json["createdAt"] as? Int64), 500)
    }

    func testRejectsOutOfOrderAndTooFastCompletions() {
        // In the past: a completion may not be recorded in the future.
        let start = Date().addingTimeInterval(-10)
        var builder = LivenessTokenBuilder(challenge: makeChallenge(["center", "blink"]), createdAt: start)
        XCTAssertThrowsError(try builder.complete("blink", at: start.addingTimeInterval(1)))
        XCTAssertThrowsError(try builder.complete("center", at: start.addingTimeInterval(0.2)))
        XCTAssertNoThrow(try builder.complete("center", at: start.addingTimeInterval(0.6)))
        XCTAssertThrowsError(try builder.encoded(), "incomplete sequence")
    }
}

// MARK: - Session client wire format

private let capture = LivenessCapture(token: "{\"id\":\"x\"}", frames: [Data("f1".utf8), Data("f2".utf8)], nonce: "n")

final class SessionMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Data) -> (Int, Data))?
    /// Extra response headers, e.g. `Date`.
    static var headers: [String: String] = [:]
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 65536)
                guard read > 0 else { break }
                body.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
        }
        let (status, data) = Self.handler!(request, body)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"].merging(Self.headers) { $1 })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SessionClientTests: XCTestCase {
    private func client() throws -> VerificationSessionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionMockURLProtocol.self]
        let credentials = try VerificationSessionCredentials(sessionURL: "https://verify.tuteliq.ai/age/?session=s1&token=t1")
        return VerificationSessionClient(credentials: credentials, session: URLSession(configuration: config))
    }

    func testValidateDocumentSendsFieldsBeforeFileWithSessionToken() async throws {
        var captured: (URLRequest, Data)?
        SessionMockURLProtocol.handler = { request, body in
            captured = (request, body)
            return (200, Data(#"{"valid":true,"quality":"good","issues":[],"retained":true}"#.utf8))
        }
        let result = try await client().validateDocument(Data("IMG".utf8), side: .passport, documentType: .passport, captureSource: .camera)
        XCTAssertTrue(result.retained)

        let (request, body) = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.tuteliq.ai/api/v1/verify/session/s1/validate-document")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
        let text = String(decoding: body, as: UTF8.self)
        let side = try XCTUnwrap(text.range(of: "name=\"side\"\r\n\r\npassport"))
        let file = try XCTUnwrap(text.range(of: "name=\"document\"; filename=\"document.jpg\"\r\nContent-Type: image/jpeg"))
        XCTAssertLessThan(side.lowerBound, file.lowerBound)
        XCTAssertTrue(text.contains("name=\"document_capture_source\"\r\n\r\ncamera"))
    }

    func testCaptureContextTravelsAsAFieldBeforeFiles() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"face_detected":true,"assessed":true}"#.utf8)) }
        let context = CaptureContext(
            sdk: .init(name: "my-capture-ui", version: "1.0", platform: "ios", osVersion: "26.0", deviceModel: "iPhone17,1"),
            pipeline: "custom", pipelineVersion: 3,
            face: .init(camera: "front_wide", livenessEngine: "custom", livenessEngineVersion: 1)
        )
        _ = try await client().validateSelfie(Data("IMG".utf8), liveness: nil, context: context)
        let text = String(decoding: body, as: UTF8.self)
        let field = try XCTUnwrap(text.range(of: "name=\"capture_context\"\r\n\r\n{"))
        let file = try XCTUnwrap(text.range(of: "name=\"selfie\""))
        XCTAssertLessThan(field.lowerBound, file.lowerBound)
        XCTAssertTrue(text.contains("\"pipeline_version\":3"))
        XCTAssertTrue(text.contains("\"liveness_engine\":\"custom\""))
    }

    func testFrameKindsTravelWithTheFrames() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"face_detected":true,"assessed":true}"#.utf8)) }
        let capture = LivenessCapture(token: "{}", frames: [Data("A".utf8), Data("B".utf8)], nonce: "n", frameKinds: [.blinkClosed, .blinkOpen])
        _ = try await client().validateSelfie(Data("IMG".utf8), liveness: capture)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"liveness_frame_kinds\"\r\n\r\n[\"blink_closed\",\"blink_open\"]"), text)
    }

    func testMismatchedFrameKindsAreDropped() {
        let capture = LivenessCapture(token: "{}", frames: [Data("A".utf8)], nonce: "n", frameKinds: [.center, .smile])
        XCTAssertEqual(capture.frameKinds, [])
        XCTAssertNil(capture.labeledFrames.first?.kind)
    }

    func testNoCaptureContextNoField() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"quality":"good","issues":[],"retained":true}"#.utf8)) }
        _ = try await client().validateDocument(Data("IMG".utf8), side: .passport, documentType: .passport, captureSource: .camera)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("capture_context"))
    }

    func testSubmitSendsPassportAsFrontAndPassport() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"ok":true,"status":"completed"}"#.utf8)) }
        _ = try await client().submit(SessionSubmission(
            documentType: .passport, documentFront: Data("P".utf8), selfie: Data("S".utf8), liveness: capture
        ))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"id_front\"; filename=\"id_front.jpg\""))
        XCTAssertTrue(text.contains("name=\"passport\"; filename=\"passport.jpg\""))
        XCTAssertTrue(text.contains("name=\"liveness_token\""))
        XCTAssertEqual(text.components(separatedBy: "name=\"liveness_frame\"").count - 1, 2)
        XCTAssertFalse(text.contains("name=\"id_back\""))
    }

    func testMapsSessionErrorCodes() async throws {
        SessionMockURLProtocol.handler = { _, _ in (410, Data(#"{"error":{"code":"VERIFY_11007","message":"Session expired"}}"#.utf8)) }
        do {
            _ = try await client().fetchMode()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? VerificationError, .sessionExpired)
        }
        XCTAssertEqual(VerificationSessionClient.error(status: 429, body: Data(), retryAfter: "12"), .rateLimited(retryAfter: 12))
    }

    func testValidateChipReturnsNilWhenServerLacksTheRoute() async throws {
        SessionMockURLProtocol.handler = { _, _ in (404, Data(#"{"error":{"code":"NF_5002","message":"Route POST /api/v1/verify/session/s1/validate-chip not found"}}"#.utf8)) }
        let result = try await client().validateChip([.dg1: Data([0x61, 0x00]), .sod: Data([0x77, 0x00])], documentType: .passport)
        XCTAssertNil(result)
    }

    func testFetchChipChallengeDecodesTheChallengeBytes() async throws {
        var captured: URLRequest?
        SessionMockURLProtocol.handler = { request, _ in
            captured = request
            return (200, Data(#"{"challenge":"0a1b2c3d4e5f6071","expires_at":1760000120000}"#.utf8))
        }
        let challenge = try await client().fetchChipChallenge()
        XCTAssertEqual(challenge.challenge, Data([0x0A, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F, 0x60, 0x71]))
        XCTAssertEqual(challenge.expiresAt, Date(timeIntervalSince1970: 1_760_000_120))
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.tuteliq.ai/api/v1/verify/session/s1/chip-challenge")
        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
    }

    func testAMalformedChipChallengeIsAnError() async throws {
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"challenge":"xyz","expires_at":1}"#.utf8)) }
        do {
            _ = try await client().fetchChipChallenge()
            XCTFail("Expected error")
        } catch {}
    }

    func testStartChipAuthenticationSendsDG14AndDecodesTheCommands() async throws {
        var captured: URLRequest?
        var sent = Data()
        SessionMockURLProtocol.handler = { request, body in
            captured = request
            sent = body
            return (200, Data(#"{"commands":["002241a4","00860000"],"protected_command":"0cb08100","expires_at":1760000120000}"#.utf8))
        }
        let start = try await client().startChipAuthentication(dg14: Data([0x6E, 0x01, 0x02]))
        XCTAssertEqual(start.commands, [Data([0x00, 0x22, 0x41, 0xA4]), Data([0x00, 0x86, 0x00, 0x00])])
        XCTAssertEqual(start.protectedCommand, Data([0x0C, 0xB0, 0x81, 0x00]))
        XCTAssertEqual(start.expiresAt, Date(timeIntervalSince1970: 1_760_000_120))
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.tuteliq.ai/api/v1/verify/session/s1/chip-authentication")
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: String])
        XCTAssertEqual(json, ["dg14": "bgEC"])
    }

    func testMalformedChipAuthenticationCommandsAreAnError() async throws {
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"commands":["zz"],"protected_command":"0c","expires_at":1}"#.utf8)) }
        do {
            _ = try await client().startChipAuthentication(dg14: Data([0x6E]))
            XCTFail("Expected error")
        } catch {}
    }

    func testValidateChipSendsTheChipAuthenticationResponse() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"issues":[],"retained":true,"usable_as_document":true}"#.utf8)) }
        _ = try await client().validateChip([.dg1: Data([0x61]), .dg14: Data([0x6E]), .sod: Data([0x77])], documentType: .passport,
                                            chipAuthenticationResponse: Data([0x99, 0x02, 0x90, 0x00]))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"ca_response\"; filename=\"ca_response.bin\"\r\nContent-Type: application/octet-stream"), text)
        XCTAssertFalse(text.contains("aa_signature"))
    }

    func testValidateChipSendsTheActiveAuthenticationSignature() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"issues":[],"retained":true,"usable_as_document":true}"#.utf8)) }
        let result = try await client().validateChip([.dg1: Data([0x61]), .dg15: Data([0x6F]), .sod: Data([0x77])], documentType: .passport,
                                                     activeAuthenticationSignature: Data([0xAA, 0xBB]))
        XCTAssertEqual(result?.usableAsDocument, true)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"aa_signature\"; filename=\"aa_signature.bin\"\r\nContent-Type: application/octet-stream"), text)
    }

    func testValidateChipWithoutASignatureSendsNone() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"issues":[],"retained":true}"#.utf8)) }
        let result = try await client().validateChip([.dg1: Data([0x61]), .sod: Data([0x77])], documentType: .passport)
        XCTAssertNil(result?.usableAsDocument)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("aa_signature"))
    }

    func testModeCarriesTheSessionChipPolicy() async throws {
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"verification_mode":"full","chip_policy":"instead_of_photo"}"#.utf8)) }
        let policy = try await client().fetchMode().chipPolicy
        XCTAssertEqual(policy, .insteadOfPhoto)
    }

    func testAnUnknownOrMissingChipPolicyIsNil() async throws {
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"verification_mode":"full","chip_policy":"something_new","lang":"sv"}"#.utf8)) }
        let mode = try await client().fetchMode()
        XCTAssertNil(mode.chipPolicy)
        XCTAssertEqual(mode.lang, "sv")
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"verification_mode":"liveness_only"}"#.utf8)) }
        let older = try await client().fetchMode()
        XCTAssertNil(older.chipPolicy)
    }

    func testSubmitSaysWhyItNeedsADocument() async throws {
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"ok":true,"status":"document_required","reason":"chip_not_usable"}"#.utf8)) }
        let result = try await client().submit(SessionSubmission(documentType: .passport))
        XCTAssertEqual(result.status, .documentRequired)
        XCTAssertEqual(result.reason, .chipNotUsable)
        SessionMockURLProtocol.handler = { _, _ in (200, Data(#"{"ok":true,"status":"document_required","reason":"later_reason"}"#.utf8)) }
        let unknown = try await client().submit(SessionSubmission(documentType: .passport))
        XCTAssertNil(unknown.reason)
    }

    func testValidateChipUploadsRawFiles() async throws {
        var body = Data()
        SessionMockURLProtocol.handler = { _, data in body = data; return (200, Data(#"{"valid":true,"issues":[],"retained":true}"#.utf8)) }
        let result = try await client().validateChip([.com: Data([0x60]), .dg1: Data([0x61]), .dg2: Data([0x75]), .sod: Data([0x77])], documentType: .passport)
        XCTAssertEqual(result?.retained, true)
        let text = String(decoding: body, as: UTF8.self)
        for field in ["ef_com", "dg1", "dg2", "ef_sod"] {
            XCTAssertTrue(text.contains("name=\"\(field)\"; filename=\"\(field).bin\"\r\nContent-Type: application/octet-stream"), field)
        }
    }
}
