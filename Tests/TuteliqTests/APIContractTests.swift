@testable import Tuteliq
import XCTest

/// Requests and models checked against what the API serves and accepts.
extension TuteliqTests {
    // MARK: - Voice stream

    func testVoiceStreamUsesTheVersionedPathOnTheClientsHost() throws {
        let client = try Tuteliq(apiKey: Self.placeholder)
        XCTAssertEqual(client.voiceStream().baseURL, "wss://api.tuteliq.ai/api/v1/safety/voice/stream")

        let staging = try Tuteliq(apiKey: Self.placeholder, baseURL: "https://staging.example.com/")
        XCTAssertEqual(staging.voiceStream().baseURL, "wss://staging.example.com/api/v1/safety/voice/stream")

        let local = try Tuteliq(apiKey: Self.placeholder, baseURL: "http://localhost:8080")
        XCTAssertEqual(local.voiceStream().baseURL, "ws://localhost:8080/api/v1/safety/voice/stream")
    }

    // MARK: - analyze(include:)

    func testAnalyzeRejectsTypesItCannotRunBeforeSending() async throws {
        var sent = 0
        let client = try makeClient { _ in
            sent += 1
            return self.mockResponse(json: [:])
        }
        for type in [AnalysisType.grooming, .emotions, .voice, .image] {
            do {
                _ = try await client.analyze(AnalyzeInput(content: "hi", include: [.bullying, type]))
                XCTFail("\(type) must not be skipped silently")
            } catch let TuteliqError.validationError(message, _) {
                XCTAssertTrue(message.contains(type.rawValue), message)
            }
        }
        do {
            _ = try await client.analyze(AnalyzeInput(content: "hi", include: []))
            XCTFail("an empty include must not read as no concerns")
        } catch TuteliqError.validationError {}
        XCTAssertEqual(sent, 0, "no request may be sent for a rejected include")
    }

    // MARK: - Grooming analysis status

    func testGroomingEngineErrorIsVisible() throws {
        let json: [String: Any] = [
            "grooming_risk": "none", "confidence": 0, "flags": [] as [String],
            "rationale": "The analysis engine could not produce a verdict.",
            "risk_score": 0, "recommended_action": "flag_for_review",
            "action_detail": "Treat this as unresolved, not as safe.",
            "analysis_status": "engine_error",
        ]
        let result = try JSONDecoder().decode(GroomingResult.self, from: jsonData(json))
        XCTAssertEqual(result.analysisStatus, "engine_error")
        XCTAssertEqual(result.groomingRisk, .none)
        XCTAssertEqual(result.recommendedAction, .flagForReview)
    }

    // MARK: - Query encoding

    func testPlusInAQueryValueIsEncoded() async throws {
        var seen: URLRequest?
        let client = try makeClient { request in
            seen = request
            return self.mockResponse(json: [:])
        }
        _ = try? await client.getIncidentsOverview(from: "2026-01-01T00:00:00+01:00")
        let url = try XCTUnwrap(seen?.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = try XCTUnwrap(components?.percentEncodedQuery)
        XCTAssertTrue(query.contains("from=2026-01-01T00:00:00%2B01:00"), query)
        XCTAssertEqual(components?.queryItems?.first { $0.name == "from" }?.value, "2026-01-01T00:00:00+01:00")
    }

    // MARK: - analyseMulti evidence

    func testAnalyseMultiPassesIncludeEvidenceThrough() async throws {
        var bodies: [[String: Any]] = []
        let client = try makeClient { request in
            if let data = Self.body(of: request),
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                bodies.append(body)
            }
            return self.mockResponse(json: [:])
        }
        _ = try? await client.analyseMulti(AnalyseMultiInput(content: "hi", detections: [.bullying], includeEvidence: false))
        _ = try? await client.analyseMulti(AnalyseMultiInput(content: "hi", detections: [.bullying]))

        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual((bodies.first?["options"] as? [String: Any])?["include_evidence"] as? Bool, false,
                       "an explicit false must reach the API, which defaults evidence on")
        XCTAssertNil((bodies.last?["options"] as? [String: Any])?["include_evidence"], "unset leaves the API default")
    }

    // MARK: - Batch review

    func testBatchReviewSendsTheModerator() async throws {
        var body: [String: Any]?
        let client = try makeClient { request in
            if let data = Self.body(of: request) {
                body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return self.mockResponse(json: [:])
        }
        _ = try? await client.batchReviewIncidents(BatchReviewIncidentsInput(
            incidentIds: ["inc_1"], action: .resolve, reasonCode: .confirmedAccurate, moderatorExternalId: "mod_jane"
        ))
        XCTAssertEqual(body?["moderator_external_id"] as? String, "mod_jane")
    }

    // MARK: - Values the API uses

    func testEnumsCarryTheAPIsValues() {
        XCTAssertEqual(IncidentStatus.reviewed.rawValue, "reviewed")
        XCTAssertEqual(
            [WebhookEventType.verificationCompleted, .minorDetected, .csamDetected, .csamCritical].map(\.rawValue),
            ["verification.completed", "minor.detected", "csam.detected", "csam.critical"]
        )
        XCTAssertEqual(
            [Detection.distressSignals, .tfgbv, .syntheticContent].map(\.rawValue),
            ["distress-signals", "tfgbv", "synthetic-content"]
        )
    }

    // MARK: - GET cache

    func testAWriteClearsTheCache() async throws {
        var gets = 0
        let client = try makeClient(cacheTTL: 60) { request in
            if request.httpMethod == "GET" {
                gets += 1
            }
            return self.mockResponse(json: ["success": true, "config": ["a": gets]])
        }
        _ = try await client.getPolicy()
        _ = try await client.getPolicy()
        XCTAssertEqual(gets, 1, "a repeated read is cached")

        _ = try await client.setPolicy(["a": AnyCodable(2)])
        _ = try await client.getPolicy()
        XCTAssertEqual(gets, 2, "a read after a write must not return the cached answer")
    }

    func testReadsThatChangeWhileWatchedAreNotCached() async throws {
        var gets = 0
        let client = try makeClient(cacheTTL: 60) { _ in
            gets += 1
            return self.mockResponse(json: [:])
        }
        for _ in 0 ..< 2 {
            _ = try? await client.getVerificationSession(id: "vs_1")
            _ = try? await client.getIncident(id: "inc_1")
            _ = try? await client.getDetectionSettings()
        }
        XCTAssertEqual(gets, 6)
        XCTAssertTrue(Tuteliq.isCacheable("/api/v1/policy"))
    }

    // MARK: - Multipart

    func testMultipartFilenameCannotBreakTheHeader() async throws {
        var body = ""
        let client = try makeClient { request in
            body = Self.body(of: request).map { String(decoding: $0, as: UTF8.self) } ?? ""
            return self.mockResponse(json: [:])
        }
        _ = try? await client.analyzeImage(AnalyzeImageInput(
            file: Data("IMG".utf8), filename: "a\"b\r\nX-Injected: 1.png"
        ))
        XCTAssertTrue(body.contains("filename=\"a%22b%0D%0AX-Injected: 1.png\""), body)
        XCTAssertFalse(body.contains("\r\nX-Injected"))
    }

    func testMimeTypesForCommonMedia() {
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "clip.m4v"), "video/x-m4v")
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "clip.mpeg"), "video/mpeg")
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "voice.aac"), "audio/aac")
    }

    /// Not a credential: the same placeholder the other tests use.
    private static let placeholder = ["test", "api", "key", "12345"].joined(separator: "-")

    /// `URLProtocol` hands the body over as a stream.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
