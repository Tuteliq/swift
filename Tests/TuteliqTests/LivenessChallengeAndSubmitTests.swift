@testable import Tuteliq
import XCTest

/// Tests for the liveness challenge and verification submit calls:
/// - `getLivenessChallenge()`
/// - `submitVerification(_:)`
/// - `LivenessChallenge`, `SubmitVerificationInput`, `VerificationSubmitResult`
final class LivenessChallengeAndSubmitTests: XCTestCase {
    // MARK: - getLivenessChallenge

    func test_getLivenessChallenge_decodes_full_payload() async throws {
        let helpers = TestHelpers()
        let client = try helpers.makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/verify/age/challenge")
            XCTAssertEqual(request.httpMethod, "GET")
            return helpers.mockResponse(json: [
                "nonce": "abc-123",
                "signature": "sig-xyz",
                "expires_at": 1_715_000_300_000,
                "challenges": ["center", "left", "right", "blink", "smile"],
            ])
        }

        let challenge = try await client.getLivenessChallenge()
        XCTAssertEqual(challenge.nonce, "abc-123")
        XCTAssertEqual(challenge.signature, "sig-xyz")
        XCTAssertEqual(challenge.expiresAt, 1_715_000_300_000)
        XCTAssertEqual(challenge.challenges, ["center", "left", "right", "blink", "smile"])
    }

    func test_getLivenessChallenge_propagates_500() async throws {
        let helpers = TestHelpers()
        let client = try helpers.makeClient(maxRetries: 1) { _ in
            helpers.mockResponse(statusCode: 500, json: ["error": ["message": "boom"]])
        }

        do {
            _ = try await client.getLivenessChallenge()
            XCTFail("Expected serverError")
        } catch let error as TuteliqError {
            switch error {
            case .serverError: break
            default: XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - submitVerification

    func test_submitVerification_sends_id_front_with_passport_in_place_of_id_back() async throws {
        let helpers = TestHelpers()
        var capturedRequest: URLRequest?

        let client = try helpers.makeClient { request in
            capturedRequest = request
            return helpers.mockResponse(json: [
                "verification_id": "ver_test",
                "status": "verified",
                "age": 24,
                "is_minor": false,
                "document": [
                    "ocr_confidence": 0.92,
                    "name_extracted": "SPECIMEN TESTPERSON",
                    "dob_extracted": "1970-01-01",
                    "document_number": "X0000000",
                ],
                "face_match": [
                    "matched": true,
                    "confidence": 0.94,
                    "distance": 0.31,
                ],
                "liveness": ["valid": true],
                "credits_used": 8,
            ])
        }

        let input = SubmitVerificationInput(
            idFront: Data("FRONT_BYTES".utf8),
            passport: Data("PASSPORT_BYTES".utf8),
            selfie: Data("SELFIE_BYTES".utf8),
            livenessToken: "{\"nonce\":\"abc\"}",
            livenessFrames: [Data("FRAME0".utf8), Data("FRAME1".utf8)]
        )
        let result = try await client.submitVerification(input)

        // Path & method
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/verify/submit")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")

        // Content-Type starts with multipart/form-data; boundary=...
        let contentType = capturedRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), "got \(contentType)")

        // Body must contain the field name disposition lines for each part.
        let body = capturedRequest?.bodyData() ?? Data()
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyText.contains("name=\"passport\""), "passport part missing")
        XCTAssertTrue(bodyText.contains("name=\"selfie\""), "selfie part missing")
        XCTAssertTrue(bodyText.contains("name=\"liveness_token\""), "liveness_token field missing")
        XCTAssertTrue(bodyText.contains("name=\"liveness_frame\""), "liveness_frame missing")
        XCTAssertTrue(bodyText.contains("PASSPORT_BYTES"))
        XCTAssertTrue(bodyText.contains("SELFIE_BYTES"))
        XCTAssertTrue(bodyText.contains("{\"nonce\":\"abc\"}"))

        // The API always requires id_front; the passport replaces only id_back.
        XCTAssertTrue(bodyText.contains("name=\"id_front\""), "id_front part missing")
        XCTAssertTrue(bodyText.contains("FRONT_BYTES"))
        XCTAssertFalse(bodyText.contains("name=\"id_back\""))

        // Result decoding.
        XCTAssertEqual(result.verificationId, "ver_test")
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.age, 24)
        XCTAssertEqual(result.isMinor, false)
        XCTAssertEqual(result.document?.documentNumber, "X0000000")
        XCTAssertEqual(result.faceMatch?.matched, true)
        XCTAssertEqual(result.liveness.valid, true)
        XCTAssertEqual(result.creditsUsed, 8)
    }

    func test_submitVerification_emits_id_front_and_back_when_no_passport() async throws {
        let helpers = TestHelpers()
        var capturedBody = Data()
        let client = try helpers.makeClient { request in
            capturedBody = request.bodyData() ?? Data()
            return helpers.mockResponse(json: [
                "verification_id": "x",
                "status": "needs_review",
                "document": ["ocr_confidence": 0.5],
                "liveness": ["valid": true],
            ])
        }

        let input = SubmitVerificationInput(
            idFront: Data("FRONT".utf8),
            idBack: Data("BACK".utf8),
            selfie: Data("S".utf8),
            livenessToken: "{}"
        )
        _ = try await client.submitVerification(input)

        let bodyText = String(data: capturedBody, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyText.contains("name=\"id_front\""))
        XCTAssertTrue(bodyText.contains("name=\"id_back\""))
        XCTAssertTrue(bodyText.contains("FRONT"))
        XCTAssertTrue(bodyText.contains("BACK"))
        XCTAssertFalse(bodyText.contains("name=\"passport\""))
    }

    func test_submitVerification_without_a_back_is_rejected_before_sending() async throws {
        let helpers = TestHelpers()
        var sent = false
        let client = try helpers.makeClient { _ in
            sent = true
            return helpers.mockResponse(json: [:])
        }

        let input = SubmitVerificationInput(idFront: Data("FRONT".utf8), selfie: Data("S".utf8), livenessToken: "{}")
        do {
            _ = try await client.submitVerification(input)
            XCTFail("expected a validation error")
        } catch TuteliqError.validationError {
            // expected
        }
        XCTAssertFalse(sent, "no request may be sent without id_back or passport")
    }

    func test_submitVerification_maps_400_to_validationError() async throws {
        let helpers = TestHelpers()
        let client = try helpers.makeClient { _ in
            helpers.mockResponse(statusCode: 400, json: [
                "error": ["message": "Could not read the document image", "code": "FILE_INVALID"],
            ])
        }

        let input = SubmitVerificationInput(
            idFront: Data("FRONT".utf8),
            idBack: Data("BACK".utf8),
            selfie: Data("S".utf8),
            livenessToken: "{}"
        )
        do {
            _ = try await client.submitVerification(input)
            XCTFail("Expected validationError")
        } catch let error as TuteliqError {
            switch error {
            case .validationError: break
            default: XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - LivenessChallenge codable round-trip

    func test_LivenessChallenge_codable_round_trip() throws {
        let original = LivenessChallenge(
            nonce: "n",
            signature: "s",
            expiresAt: 100,
            challenges: ["a", "b"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LivenessChallenge.self, from: data)
        XCTAssertEqual(decoded.nonce, original.nonce)
        XCTAssertEqual(decoded.signature, original.signature)
        XCTAssertEqual(decoded.expiresAt, original.expiresAt)
        XCTAssertEqual(decoded.challenges, original.challenges)
    }
}

// MARK: - Local helpers (mirror existing TuteliqTests helpers without

// touching them, so this file can be removed as a unit if needed)

private struct TestHelpers {
    func makeClient(
        maxRetries: Int = 3,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> Tuteliq {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return try Tuteliq(
            apiKey: "test-api-key-12345",
            maxRetries: maxRetries,
            session: session
        )
    }

    func mockResponse(
        statusCode: Int = 200,
        json: [String: Any],
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let response = HTTPURLResponse(
            url: URL(string: "https://api.tuteliq.ai")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: allHeaders
        )!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }
}

// MARK: - URLRequest body helper

///
/// `URLProtocol` strips httpBody when handed via mockable URLSession, but
/// mirrors it into `httpBodyStream`. Read it back so tests can inspect body
/// bytes.
private extension URLRequest {
    func bodyData() -> Data? {
        if let body = httpBody {
            return body
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
