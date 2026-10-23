@testable import Tuteliq
import XCTest

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("No request handler set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Helpers

extension TuteliqTests {
    func makeClient(
        maxRetries: Int = 3,
        cacheTTL: TimeInterval = 0,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> Tuteliq {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return try Tuteliq(
            apiKey: "test-api-key-12345",
            maxRetries: maxRetries,
            cacheTTL: cacheTTL,
            session: session
        )
    }

    func jsonData(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
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
        return (response, jsonData(json))
    }
}

// MARK: - Tests

final class TuteliqTests: XCTestCase {
    // MARK: - Initialization

    func testInitialization() throws {
        let client = try Tuteliq(apiKey: "test-api-key-12345")
        XCTAssertNotNil(client)
    }

    func testInitializationWithCustomOptions() throws {
        let client = try Tuteliq(
            apiKey: "test-api-key-12345",
            baseURL: "https://staging.tuteliq.ai",
            timeout: 60,
            maxRetries: 5,
            retryDelay: 2
        )
        XCTAssertNotNil(client)
    }

    func testInitializationThrowsOnEmptyKey() {
        XCTAssertThrowsError(try Tuteliq(apiKey: "")) { error in
            guard case let TuteliqError.validationError(msg, _) = error else {
                XCTFail("Expected validationError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("required"))
        }
    }

    func testInitializationThrowsOnShortKey() {
        XCTAssertThrowsError(try Tuteliq(apiKey: "short")) { error in
            guard case let TuteliqError.validationError(msg, _) = error else {
                XCTFail("Expected validationError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("too short"))
        }
    }

    func testInitializationThrowsOnInvalidBaseURL() {
        XCTAssertThrowsError(try Tuteliq(apiKey: "test-api-key-12345", baseURL: "")) { error in
            guard case TuteliqError.validationError = error else {
                XCTFail("Expected validationError, got \(error)")
                return
            }
        }
    }

    // MARK: - Enum Raw Values

    func testSeverityEnum() {
        XCTAssertEqual(Severity.low.rawValue, "low")
        XCTAssertEqual(Severity.critical.rawValue, "critical")
    }

    func testGroomingRiskEnum() {
        XCTAssertEqual(GroomingRisk.none.rawValue, "none")
        XCTAssertEqual(GroomingRisk.high.rawValue, "high")
    }

    func testRiskLevelEnum() {
        XCTAssertEqual(RiskLevel.safe.rawValue, "safe")
        XCTAssertEqual(RiskLevel.critical.rawValue, "critical")
    }

    func testEmotionTrendEnum() {
        XCTAssertEqual(EmotionTrend.improving.rawValue, "improving")
        XCTAssertEqual(EmotionTrend.worsening.rawValue, "worsening")
    }

    func testAudienceEnum() {
        XCTAssertEqual(Audience.child.rawValue, "child")
        XCTAssertEqual(Audience.parent.rawValue, "parent")
        XCTAssertEqual(Audience.platform.rawValue, "platform")
    }

    func testRecommendedActionEnum() {
        XCTAssertEqual(RecommendedAction.none.rawValue, "none")
        XCTAssertEqual(RecommendedAction.monitor.rawValue, "monitor")
        XCTAssertEqual(RecommendedAction.flagForReview.rawValue, "flag_for_review")
        XCTAssertEqual(RecommendedAction.block.rawValue, "block")
        XCTAssertEqual(RecommendedAction.immediateIntervention.rawValue, "immediate_intervention")
    }

    func testRecommendedActionDecodesLegacyAndUnknownValues() throws {
        func decode(_ raw: String) throws -> RecommendedAction {
            try JSONDecoder().decode(RecommendedAction.self, from: Data("\"\(raw)\"".utf8))
        }
        XCTAssertEqual(try decode("flag_for_moderator"), .flagForReview)
        XCTAssertEqual(try decode("no_action"), .none)
        // An unrecognised verdict must reach a human, not vanish or fail decoding.
        XCTAssertEqual(try decode("quarantine"), .flagForReview)
    }

    func testRecommendedActionOrderingAndActionable() {
        XCTAssertEqual(RecommendedAction.strongest([.monitor, nil, .block, .flagForReview]), .block)
        XCTAssertEqual(RecommendedAction.strongest([]), .none)
        XCTAssertFalse(RecommendedAction.monitor.isActionable)
        XCTAssertTrue(RecommendedAction.flagForReview.isActionable)
        XCTAssertTrue(RecommendedAction.immediateIntervention.isActionable)
    }

    func testWebhookEventTypeEnum() {
        XCTAssertEqual(WebhookEventType.incidentCritical.rawValue, "incident.critical")
        XCTAssertEqual(WebhookEventType.groomingDetected.rawValue, "grooming.detected")
    }

    func testAnalysisTypeEnum() {
        XCTAssertEqual(AnalysisType.bullying.rawValue, "bullying")
        XCTAssertEqual(AnalysisType.emotions.rawValue, "emotions")
    }

    // MARK: - Model Construction

    func testDetectBullyingInput() {
        let input = DetectBullyingInput(
            content: "Test message",
            context: AnalysisContext(platform: "chat"),
            externalId: "msg_123",
            customerId: "cust_456",
            metadata: ["user_id": "user_789"]
        )
        XCTAssertEqual(input.content, "Test message")
        XCTAssertEqual(input.externalId, "msg_123")
        XCTAssertEqual(input.customerId, "cust_456")
        XCTAssertNotNil(input.metadata)
        XCTAssertEqual(input.metadata?["user_id"]?.value as? String, "user_789")
    }

    func testAnalyzeInput() {
        let input = AnalyzeInput(content: "Test", include: [.bullying, .unsafe])
        XCTAssertEqual(input.content, "Test")
        XCTAssertEqual(input.include?.count, 2)
    }

    func testGroomingMessage() {
        let msg = GroomingMessage(role: .adult, content: "Hello")
        XCTAssertEqual(msg.role, .adult)
        XCTAssertEqual(msg.content, "Hello")
    }

    func testBatchItem() {
        let item = BatchItem.bullying(id: "1", text: "test")
        if case let .bullying(id, text, _) = item {
            XCTAssertEqual(id, "1")
            XCTAssertEqual(text, "test")
        } else {
            XCTFail("Expected bullying case")
        }
    }

    func testCreateWebhookInput() {
        let input = CreateWebhookInput(
            name: "Test Hook",
            url: "https://example.com/webhook",
            events: [.incidentCritical, .groomingDetected]
        )
        XCTAssertEqual(input.name, "Test Hook")
        XCTAssertEqual(input.events.count, 2)
    }

    // MARK: - AnyCodable

    func testAnyCodableEncodeDecode() throws {
        let original: [String: AnyCodable] = [
            "string": AnyCodable("hello"),
            "int": AnyCodable(42),
            "double": AnyCodable(3.14),
            "bool": AnyCodable(true),
            "array": AnyCodable([1, 2, 3]),
            "dict": AnyCodable(["nested": "value"]),
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["string"]?.value as? String, "hello")
        XCTAssertEqual(decoded["int"]?.value as? Int, 42)
        XCTAssertEqual(decoded["bool"]?.value as? Bool, true)
        XCTAssertNotNil(decoded["dict"]?.value as? [String: Any])
    }

    func testAnyCodableNull() throws {
        let data = try XCTUnwrap("null".data(using: .utf8))
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertTrue(decoded.value is NSNull)
    }

    // MARK: - JSON Decoding (API Response Models)

    func testBullyingResultDecoding() throws {
        let json: [String: Any] = [
            "is_bullying": true,
            "bullying_type": ["verbal", "exclusion"],
            "confidence": 0.87,
            "severity": "high",
            "rationale": "Contains exclusionary language",
            "recommended_action": "flag_for_review",
            "action_detail": "Queue for a moderator",
            "risk_score": 0.82,
            "external_id": "msg_123",
            "customer_id": "cust_456",
            "continuation_token": "tok_abc",
            "state_source": "token",
            "trajectory_risk": 0.74,
            "trajectory": "rising",
            "severity_series": [0.05, 0.65, 0.75],
            "profanity": ["detected": true, "matches": ["damn"]],
            "risk_terms": ["detected": true, "matches": [["term": "kill", "category": "violence"]]],
            "support": [
                "country": "GB",
                "helplines": [["name": "Childline", "number": "0800 1111"]],
                "response_guide": ["immediateActions": ["Talk to a trusted adult"], "resources": []],
            ],
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(BullyingResult.self, from: data)

        XCTAssertTrue(result.isBullying)
        XCTAssertEqual(result.bullyingType, ["verbal", "exclusion"])
        XCTAssertEqual(result.confidence, 0.87)
        XCTAssertEqual(result.severity, .high)
        XCTAssertEqual(result.riskScore, 0.82)
        XCTAssertEqual(result.recommendedAction, .flagForReview)
        XCTAssertEqual(result.actionDetail, "Queue for a moderator")
        XCTAssertEqual(result.externalId, "msg_123")
        XCTAssertEqual(result.customerId, "cust_456")
        XCTAssertEqual(result.continuationToken, "tok_abc")
        XCTAssertEqual(result.stateSource, .token)
        XCTAssertEqual(result.trajectoryRisk, 0.74)
        XCTAssertEqual(result.trajectory, .rising)
        XCTAssertEqual(result.severitySeries, [0.05, 0.65, 0.75])
        XCTAssertEqual(result.profanity?.matches, ["damn"])
        XCTAssertEqual(result.riskTerms?.matches.first?.category, "violence")
        XCTAssertEqual(result.support?.helplines.first?.name, "Childline")
        XCTAssertEqual(result.support?.responseGuide?.immediateActions, ["Talk to a trusted adult"])
    }

    func testGroomingResultDecoding() throws {
        let json: [String: Any] = [
            "grooming_risk": "high",
            "confidence": 0.91,
            "flags": ["age_inappropriate", "isolation_attempt"],
            "rationale": "Detected grooming tactics",
            "risk_score": 0.88,
            "recommended_action": "immediate_intervention",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(GroomingResult.self, from: data)

        XCTAssertEqual(result.groomingRisk, .high)
        XCTAssertEqual(result.flags.count, 2)
        XCTAssertEqual(result.riskScore, 0.88)
    }

    func testUnsafeResultDecoding() throws {
        let json: [String: Any] = [
            "unsafe": true,
            "categories": ["self_harm", "violence"],
            "severity": "critical",
            "confidence": 0.95,
            "risk_score": 0.93,
            "rationale": "Contains self-harm references",
            "recommended_action": "immediate_intervention",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(UnsafeResult.self, from: data)

        XCTAssertTrue(result.unsafe)
        XCTAssertEqual(result.categories, ["self_harm", "violence"])
        XCTAssertEqual(result.severity, .critical)
    }

    func testEmotionsResultDecoding() throws {
        let json: [String: Any] = [
            "dominant_emotions": ["sadness", "anxiety"],
            "emotion_scores": ["sadness": 0.8, "anxiety": 0.6, "anger": 0.2],
            "trend": "worsening",
            "summary": "Child appears distressed",
            "recommended_followup": "Consider professional support",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(EmotionsResult.self, from: data)

        XCTAssertEqual(result.dominantEmotions, ["sadness", "anxiety"])
        XCTAssertEqual(result.trend, .worsening)
        XCTAssertEqual(result.emotionScores["sadness"], 0.8)
    }

    func testActionPlanResultDecoding() throws {
        let json: [String: Any] = [
            "audience": "parent",
            "steps": ["Step 1", "Step 2"],
            "tone": "supportive",
            "approx_reading_level": "adult",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(ActionPlanResult.self, from: data)

        XCTAssertEqual(result.audience, "parent")
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(result.readingLevel, "adult")
    }

    func testReportResultDecoding() throws {
        let json: [String: Any] = [
            "summary": "Incident summary",
            "risk_level": "high",
            "categories": ["bullying"],
            "recommended_next_steps": ["Contact school", "Monitor child"],
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(ReportResult.self, from: data)

        XCTAssertEqual(result.riskLevel, .high)
        XCTAssertEqual(result.recommendedNextSteps.count, 2)
    }

    // MARK: - Error Descriptions

    func testErrorDescriptions() {
        let errors: [(TuteliqError, String)] = [
            (.authenticationError("Invalid key"), "Authentication Error: Invalid key"),
            (.rateLimitError("Slow down"), "Rate Limit Error: Slow down"),
            (.validationError("Bad input"), "Validation Error: Bad input"),
            (.notFoundError("Not here"), "Not Found: Not here"),
            (.subscriptionError("Upgrade"), "Subscription Error: Upgrade"),
            (.serverError("Oops", statusCode: 500), "Server Error (500): Oops"),
            (.timeoutError("Too slow"), "Timeout: Too slow"),
            (.networkError("No wifi"), "Network Error: No wifi"),
            (.unknownError("What"), "Error: What"),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.localizedDescription, expected)
        }
    }

    // MARK: - Network Tests (MockURLProtocol)

    func testSuccessfulBullyingDetection() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "is_bullying": false,
                "bullying_type": [] as [String],
                "confidence": 0.1,
                "severity": "low",
                "rationale": "No bullying detected",
                "recommended_action": "none",
                "risk_score": 0.05,
            ], headers: [
                "X-Request-ID": "req_abc123",
                "X-RateLimit-Limit": "1000",
                "X-RateLimit-Remaining": "999",
                "X-RateLimit-Reset": "1700000000",
                "X-Monthly-Limit": "50000",
                "X-Monthly-Used": "100",
                "X-Monthly-Remaining": "49900",
                "X-Monthly-Reset": "2026-03-01",
            ])
        }

        let result = try await client.detectBullying(content: "Hello friend")

        XCTAssertFalse(result.isBullying)
        XCTAssertEqual(result.riskScore, 0.05)
        XCTAssertEqual(client.lastRequestId, "req_abc123")
        XCTAssertEqual(client.usage?.limit, 50000)
        XCTAssertEqual(client.usage?.used, 100)
        XCTAssertEqual(client.usage?.remaining, 49900)
        XCTAssertEqual(client.usage?.reset, "2026-03-01")
        XCTAssertEqual(client.rateLimitInfo?.limit, 1000)
        XCTAssertEqual(client.rateLimitInfo?.remaining, 999)
        XCTAssertNotNil(client.lastLatency)
    }

    func testAuthenticationError() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 401, json: [
                "error": [
                    "code": "AUTH_1002",
                    "message": "API key invalid",
                ],
            ])
        }

        do {
            _ = try await client.detectBullying(content: "test")
            XCTFail("Should have thrown")
        } catch let error as TuteliqError {
            guard case let .authenticationError(msg) = error else {
                XCTFail("Expected authenticationError, got \(error)")
                return
            }
            XCTAssertEqual(msg, "API key invalid")
        }
    }

    func testSubscriptionError() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 403, json: [
                "error": [
                    "code": "SUB_7006",
                    "message": "Endpoint not available in your plan",
                ],
            ])
        }

        do {
            _ = try await client.analyzeEmotions(content: "test")
            XCTFail("Should have thrown")
        } catch let error as TuteliqError {
            guard case let .subscriptionError(msg, code) = error else {
                XCTFail("Expected subscriptionError, got \(error)")
                return
            }
            XCTAssertEqual(msg, "Endpoint not available in your plan")
            XCTAssertEqual(code, "SUB_7006")
        }
    }

    func testRateLimitError() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 429, json: [
                "error": [
                    "code": "RATE_2001",
                    "message": "Rate limit exceeded",
                ],
            ])
        }

        do {
            _ = try await client.detectBullying(content: "test")
            XCTFail("Should have thrown")
        } catch let error as TuteliqError {
            guard case .rateLimitError = error else {
                XCTFail("Expected rateLimitError, got \(error)")
                return
            }
        }
    }

    func testValidationError() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 400, json: [
                "error": [
                    "code": "VAL_3001",
                    "message": "Validation failed",
                    "details": ["field": "text", "reason": "required"],
                ],
            ])
        }

        do {
            _ = try await client.detectBullying(content: "test")
            XCTFail("Should have thrown")
        } catch let error as TuteliqError {
            guard case let .validationError(_, details) = error else {
                XCTFail("Expected validationError, got \(error)")
                return
            }
            XCTAssertNotNil(details)
        }
    }

    func testServerError() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 500, json: [
                "error": [
                    "code": "SVC_4001",
                    "message": "Internal server error",
                ],
            ])
        }

        do {
            _ = try await client.detectBullying(content: "test")
            XCTFail("Should have thrown")
        } catch let error as TuteliqError {
            guard case let .serverError(_, statusCode) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 500)
        }
    }

    func testRequestSendsCorrectHeaders() async throws {
        var capturedRequest: URLRequest?
        let client = try makeClient { request in
            capturedRequest = request
            return self.mockResponse(json: [
                "is_bullying": false,
                "bullying_type": [] as [String],
                "confidence": 0.1,
                "severity": "low",
                "rationale": "OK",
                "recommended_action": "none",
                "risk_score": 0.0,
            ])
        }

        _ = try await client.detectBullying(content: "test")

        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key-12345")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/api/v1/safety/bullying") ?? false)
    }

    func testRequestSendsTrackingFields() async throws {
        var capturedBody: [String: Any]?
        let client = try makeClient { request in
            // httpBody may be nil in URLProtocol; read from stream instead
            if let data = request.httpBody {
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buf, maxLength: 4096)
                    guard count > 0 else { break }
                    data.append(buf, count: count)
                }
                stream.close()
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return self.mockResponse(json: [
                "is_bullying": false,
                "bullying_type": [] as [String],
                "confidence": 0.1,
                "severity": "low",
                "rationale": "OK",
                "recommended_action": "none",
                "risk_score": 0.0,
            ])
        }

        _ = try await client.detectBullying(DetectBullyingInput(
            content: "test",
            externalId: "ext_1",
            customerId: "cust_2",
            metadata: ["key": "value"]
        ))

        XCTAssertEqual(capturedBody?["text"] as? String, "test")
        XCTAssertEqual(capturedBody?["external_id"] as? String, "ext_1")
        XCTAssertEqual(capturedBody?["customer_id"] as? String, "cust_2")
        let meta = capturedBody?["metadata"] as? [String: Any]
        XCTAssertEqual(meta?["key"] as? String, "value")
    }

    func testUsageWarningHeader() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "is_bullying": false,
                "bullying_type": [] as [String],
                "confidence": 0.1,
                "severity": "low",
                "rationale": "OK",
                "recommended_action": "none",
                "risk_score": 0.0,
            ], headers: [
                "X-Monthly-Limit": "1000",
                "X-Monthly-Used": "850",
                "X-Monthly-Remaining": "150",
                "X-Usage-Warning": "85% of monthly limit used",
            ])
        }

        _ = try await client.detectBullying(content: "test")

        XCTAssertEqual(client.usage?.warning, "85% of monthly limit used")
        XCTAssertEqual(client.usage?.used, 850)
    }

    // MARK: - GET Cache Tests

    func testGetCacheReturnsFromCache() async throws {
        var callCount = 0
        let client = try makeClient(cacheTTL: 60) { _ in
            callCount += 1
            return self.mockResponse(json: [
                "plans": [] as [[String: Any]],
            ])
        }

        let result1: PricingResult = try await client.getPricing()
        let result2: PricingResult = try await client.getPricing()

        XCTAssertEqual(callCount, 1, "Second call should use cache")
        XCTAssertEqual(result1.plans.count, result2.plans.count)
    }

    // MARK: - Cancellation Test

    func testCancelledTaskThrows() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(json: [
                "is_bullying": false, "bullying_type": [] as [String],
                "confidence": 0.1, "severity": "low", "rationale": "OK",
                "recommended_action": "none", "risk_score": 0.0,
            ])
        }

        let task = Task {
            try await client.detectBullying(content: "test")
        }
        // Cancel immediately — Task.checkCancellation() at top of retry loop should throw
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            break // May succeed if cancellation check is too late; that's acceptable
        case let .failure(error):
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }

    // MARK: - RiskLevel Consistency

    func testAnalyzeResultRiskLevelIsString() throws {
        let json: [String: Any] = [
            "risk_level": "high",
            "risk_score": 0.85,
            "confidence": 0.9,
            "summary": "Concerns detected",
            "recommended_action": "flag_for_moderator",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)

        XCTAssertEqual(result.riskLevel, .high)
        XCTAssertEqual(result.recommendedAction, .flagForReview)
    }

    func testReportResultRiskLevelValue() throws {
        let json: [String: Any] = [
            "summary": "Report",
            "risk_level": "critical",
            "categories": ["bullying"],
            "recommended_next_steps": ["Act now"],
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(ReportResult.self, from: data)

        XCTAssertEqual(result.riskLevel, .critical)
    }

    // MARK: - Encodable Request Body Test

    func testRequestBodyUsesSnakeCaseKeys() async throws {
        var capturedBody: [String: Any]?
        let client = try makeClient { request in
            if let data = request.httpBody {
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buf, maxLength: 4096)
                    guard count > 0 else { break }
                    data.append(buf, count: count)
                }
                stream.close()
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return self.mockResponse(json: [
                "is_bullying": false, "bullying_type": [] as [String],
                "confidence": 0.1, "severity": "low", "rationale": "OK",
                "recommended_action": "none", "risk_score": 0.0,
            ])
        }

        _ = try await client.detectBullying(DetectBullyingInput(
            content: "test",
            externalId: "ext_1",
            customerId: "cust_2"
        ))

        XCTAssertNotNil(capturedBody)
        // Verify snake_case keys from encoder
        XCTAssertNotNil(capturedBody?["external_id"], "Should use snake_case key 'external_id'")
        XCTAssertNotNil(capturedBody?["customer_id"], "Should use snake_case key 'customer_id'")
        XCTAssertNil(capturedBody?["externalId"], "Should NOT have camelCase key")
    }

    // MARK: - Request Body Shapes

    private static let benignBullying: [String: Any] = [
        "is_bullying": false, "bullying_type": [] as [String],
        "confidence": 0.1, "severity": "low", "rationale": "OK",
        "recommended_action": "none", "risk_score": 0.0,
    ]

    private func capturingClient(
        response: [String: Any],
        capture: @escaping ([String: Any]) -> Void
    ) throws -> Tuteliq {
        try makeClient { request in
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buf, maxLength: 4096)
                    guard count > 0 else { break }
                    data.append(buf, count: count)
                }
                stream.close()
            }
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                capture(body)
            }
            return self.mockResponse(json: response)
        }
    }

    func testBullyingSendsOptionsContinuationAndPriorMessages() async throws {
        var body: [String: Any] = [:]
        let client = try capturingClient(response: Self.benignBullying) { body = $0 }

        _ = try await client.detectBullying(DetectBullyingInput(
            content: "see you tomorrow",
            context: AnalysisContext(
                platform: "MyApp", country: "GB",
                priorMessages: [PriorMessage(role: "contact", text: "nobody likes you")]
            ),
            metadata: ["userName": "a"],
            supportThreshold: .medium,
            verdictOnly: true,
            continuationToken: "tok_1",
            flagProfanity: false,
            flagRiskTerms: true,
            incidentModerationEnabled: false
        ))

        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["support_threshold"] as? String, "medium")
        XCTAssertEqual(options?["verdict_only"] as? Bool, true)
        // An explicit false must reach the API: it overrides the account default.
        XCTAssertEqual(options?["flag_profanity"] as? Bool, false)
        XCTAssertEqual(options?["flag_risk_terms"] as? Bool, true)
        XCTAssertEqual(body["continuation_token"] as? String, "tok_1")
        XCTAssertNil(body["reset_conversation"], "false is omitted")
        XCTAssertEqual(body["incident_moderation_enabled"] as? Bool, false)
        let context = body["context"] as? [String: Any]
        XCTAssertEqual(context?["platform"] as? String, "MyApp - Swift SDK")
        XCTAssertEqual(context?["country"] as? String, "GB")
        let prior = context?["prior_messages"] as? [[String: Any]]
        XCTAssertEqual(prior?.first?["text"] as? String, "nobody likes you")
        // Metadata keys are the caller's and must not be snake-cased.
        XCTAssertEqual((body["metadata"] as? [String: Any])?["userName"] as? String, "a")
    }

    func testBullyingOmitsOptionsWhenNothingSet() async throws {
        var body: [String: Any] = [:]
        let client = try capturingClient(response: Self.benignBullying) { body = $0 }
        _ = try await client.detectBullying(content: "hello")
        XCTAssertNil(body["options"])
        XCTAssertNil(body["continuation_token"])
    }

    func testDetectionForwardsExplicitIncludeEvidenceFalse() async throws {
        var body: [String: Any] = [:]
        let client = try capturingClient(response: [
            "endpoint": "romance-scam", "detected": false, "severity": 0.0, "confidence": 0.9,
            "risk_score": 0.0, "level": "none", "categories": [] as [Any],
            "recommended_action": "none", "language": "en", "language_status": "stable",
        ]) { body = $0 }

        _ = try await client.detectRomanceScam(DetectionInput(content: "hi", includeEvidence: false))
        XCTAssertEqual(body["include_evidence"] as? Bool, false)
        XCTAssertEqual((body["options"] as? [String: Any])?["include_evidence"] as? Bool, false)

        _ = try await client.detectRomanceScam(DetectionInput(content: "hi", verdictOnly: true))
        XCTAssertNil(body["include_evidence"], "unset lets the server infer it from verdictOnly")
        XCTAssertEqual((body["options"] as? [String: Any])?["verdict_only"] as? Bool, true)
    }

    func testAnalyzeAggregatesStrongestAction() async throws {
        let client = try makeClient { request in
            if request.url?.path.hasSuffix("/bullying") == true {
                var json = Self.benignBullying
                json["recommended_action"] = "monitor"
                json["confidence"] = 0.4
                return self.mockResponse(json: json)
            }
            return self.mockResponse(json: [
                "unsafe": true, "categories": ["self_harm"], "severity": "high",
                "confidence": 0.8, "risk_score": 0.75, "recommended_action": "block",
            ])
        }
        let result = try await client.analyze(content: "test")
        XCTAssertEqual(result.recommendedAction, .block)
        XCTAssertEqual(result.confidence, 0.8)
        XCTAssertEqual(result.riskLevel, .high)
    }

    func testQuotaExceededIsNotRetried() async throws {
        var calls = 0
        let client = try makeClient(maxRetries: 3) { _ in
            calls += 1
            return self.mockResponse(statusCode: 429, json: [
                "error": ["code": "RATE_2003", "message": "Monthly quota exceeded"],
            ])
        }
        do {
            _ = try await client.detectBullying(content: "test")
            XCTFail("Should have thrown")
        } catch let TuteliqError.quotaExceededError(message) {
            XCTAssertEqual(message, "Monthly quota exceeded")
        }
        XCTAssertEqual(calls, 1)
    }

    func testClientSideValidation() async throws {
        let client = try makeClient { _ in
            XCTFail("Invalid input must not reach the network")
            return self.mockResponse(json: [:])
        }
        await XCTAssertThrowsValidation { _ = try await client.detectBullying(content: "") }
        await XCTAssertThrowsValidation {
            _ = try await client.detectUnsafe(content: String(repeating: "a", count: 50001))
        }
        await XCTAssertThrowsValidation { _ = try await client.detectGrooming(DetectGroomingInput(messages: [])) }
        await XCTAssertThrowsValidation { _ = try await client.batchAnalyze(BatchAnalyzeInput(items: [])) }
        await XCTAssertThrowsValidation {
            _ = try await client.updateDetectionSettings(
                UpdateDetectionSettingsInput(enabledEndpoints: ["bullying"], disabledEndpoints: ["unsafe"])
            )
        }
        await XCTAssertThrowsValidation {
            _ = try await client.reviewIncident(
                id: "inc_1",
                ReviewIncidentInput(action: .reclassify, reasonCode: .incorrectCategory, moderatorExternalId: "mod_1")
            )
        }
    }

    private func XCTAssertThrowsValidation(
        _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected validationError", file: file, line: line)
        } catch TuteliqError.validationError {
        } catch {
            XCTFail("Expected validationError, got \(error)", file: file, line: line)
        }
    }

    func testBatchSendsTextTypesAndDecodesCamelCaseTiming() async throws {
        var body: [String: Any] = [:]
        let client = try capturingClient(response: [
            "results": [["id": "a", "type": "romance_scam", "success": true, "credits_used": 1]],
            "summary": ["total": 1, "successful": 1, "failed": 0, "processingTimeMs": 42, "total_credits_used": 1],
        ]) { body = $0 }

        let result = try await client.batchAnalyze(BatchAnalyzeInput(items: [
            .text(id: "a", type: .romanceScam, text: "send the gift card codes"),
            .grooming(id: "b", messages: [GroomingMessage(role: .adult, content: "hi")], childAge: 12),
        ]))

        let items = body["items"] as? [[String: Any]]
        XCTAssertEqual(items?.first?["type"] as? String, "romance_scam")
        XCTAssertEqual((items?.first?["data"] as? [String: Any])?["text"] as? String, "send the gift card codes")
        let groomingContext = (items?.last?["data"] as? [String: Any])?["context"] as? [String: Any]
        XCTAssertEqual(groomingContext?["child_age"] as? Int, 12)
        XCTAssertEqual(result.summary.processingTimeMs, 42)
        XCTAssertEqual(result.summary.totalCreditsUsed, 1)
        XCTAssertEqual(result.results.first?.creditsUsed, 1)
    }

    func testUsageQuotaDecodesCamelCaseWireShape() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "apiKeyId": "key_1", "tier": "pro",
                "limits": ["requestsPerMinute": 100, "requestsPerMonth": 100_000, "requestsPerDay": -1],
                "current": ["requestsThisMinute": 3, "requestsToday": 50],
                "remaining": ["requestsThisMinute": 97, "requestsToday": -1],
                "resetsInSeconds": 12,
            ])
        }
        let quota = try await client.getUsageQuota()
        XCTAssertEqual(quota.limits.requestsPerMinute, 100)
        XCTAssertEqual(quota.limits.requestsPerMonth, 100_000)
        XCTAssertEqual(quota.remaining.requestsToday, -1)
        XCTAssertEqual(quota.resetsInSeconds, 12)
    }

    func testUsageSummaryDecodesCamelCaseWireShape() throws {
        let json: [String: Any] = [
            "apiKeyId": "key_1", "tier": "pro", "date": "2026-10-15",
            "usage": ["totalRequests": 10, "successRequests": 9, "errorRequests": 1],
            "quota": ["requestsPerMinute": 100, "requestsPerMonth": 100_000, "requestsPerDay": -1, "remainingToday": -1],
        ]
        let result = try JSONDecoder().decode(UsageSummaryResult.self, from: jsonData(json))
        XCTAssertEqual(result.usage.errorRequests, 1)
        XCTAssertEqual(result.quota.requestsPerMonth, 100_000)
        XCTAssertEqual(result.quota.requestsPerDay, -1)
    }

    func testMediaResultsDecodeVerdictFields() throws {
        let video: [String: Any] = [
            "frames_analyzed": 2, "duration_seconds": 4.5,
            "frame_results": [[
                "frame_index": 0, "timestamp_s": 1.5, "risk_score": 0.7, "severity": "high",
                "vision": [
                    "extracted_text": "", "visual_categories": ["violence"], "visual_severity": "high",
                    "visual_confidence": 0.9, "visual_description": "x", "contains_text": false, "contains_faces": true,
                ],
            ]],
            "categories": ["violence"],
            "flagged_timestamps": [["timestamp_s": 1.5, "reason": "violence", "severity": "high"]],
            "overall_risk_score": 0.7, "overall_severity": "high",
            "detected": true, "confidence": 0.9, "recommended_action": "flag_for_review", "rationale": "violence",
        ]
        let result = try JSONDecoder().decode(VideoAnalysisResult.self, from: jsonData(video))
        XCTAssertEqual(result.frameResults.first?.timestampSeconds, 1.5)
        XCTAssertEqual(result.flaggedTimestamps.count, 1)
        XCTAssertEqual(result.categories, ["violence"])
        XCTAssertTrue(result.recommendedAction.isActionable)
    }

    func testMimeTypeForFilename() {
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "clip.MP4"), "video/mp4")
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "anim.gif"), "image/gif")
        XCTAssertEqual(Tuteliq.mimeType(forFilename: "voice.m4a"), "audio/m4a")
        XCTAssertNil(Tuteliq.mimeType(forFilename: "notes.txt"))
    }

    func testGetEncryptionKeyReturnsNilOn404() async throws {
        let client = try makeClient(maxRetries: 1) { _ in
            self.mockResponse(statusCode: 404, json: ["error": ["code": "NOT_FOUND", "message": "No key"]])
        }
        let key = try await client.getEncryptionKey()
        XCTAssertNil(key)
    }

    func testListIncidentsBuildsQueryAndDecodes() async throws {
        var url: URL?
        let client = try makeClient { request in
            url = request.url
            return self.mockResponse(json: [
                "incidents": [[
                    "id": "inc_1", "risk_category": "bullying", "risk_level": "high", "confidence_score": 0.9,
                    "detected_patterns": ["exclusion"], "source": "text", "status": "new",
                    "created_at": "2026-10-01T00:00:00Z", "summary": "text", "_e2e_envelope_fields": ["summary"],
                ]],
                "next_cursor": NSNull(), "total_returned": 1,
            ])
        }
        let page = try await client.listIncidents(ListIncidentsInput(
            severity: .high, status: .new, externalId: "ext 1", limit: 10, includeSummary: true
        ))
        let items = try URLComponents(url: XCTUnwrap(url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "severity", value: "high")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "external_id", value: "ext 1")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "include_summary", value: "true")))
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.incidents.first?.e2eEnvelopeFields, ["summary"])
    }

    func testCreatePolicyRuleBodyShape() async throws {
        var body: [String: Any] = [:]
        let rule: [String: Any] = [
            "id": "r1", "name": "Escalate", "enabled": true, "endpoints": ["grooming"],
            "conditions": ["min_severity": "critical"], "action": ["type": "escalate", "escalate_to": "team"],
            "priority": 0, "created_at": "2026-10-01", "updated_at": "2026-10-01",
        ]
        let client = try capturingClient(response: ["success": true, "rule": rule]) { body = $0 }

        let result = try await client.createPolicyRule(CreatePolicyRuleInput(
            name: "Escalate",
            endpoints: ["grooming"],
            conditions: PolicyRuleConditions(minSeverity: .critical),
            action: PolicyRuleAction(type: .escalate, escalateTo: "team")
        ))
        XCTAssertEqual((body["conditions"] as? [String: Any])?["min_severity"] as? String, "critical")
        XCTAssertEqual((body["action"] as? [String: Any])?["escalate_to"] as? String, "team")
        XCTAssertNil((body["conditions"] as? [String: Any])?["min_risk_score"])
        XCTAssertEqual(result.rule.action.type, .escalate)
    }

    // MARK: - Keychain Storage

    #if canImport(Security)
        func testKeychainSaveRetrieveDelete() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            let testKey = "test-keychain-api-key-12345"

            // Save
            try KeychainStore.save(apiKey: testKey, service: service)

            // Retrieve
            let retrieved = KeychainStore.retrieve(service: service)
            XCTAssertEqual(retrieved, testKey)

            // Delete
            try KeychainStore.delete(service: service)

            // Verify deleted
            let afterDelete = KeychainStore.retrieve(service: service)
            XCTAssertNil(afterDelete)
        }

        func testKeychainSaveUpdatesExistingKey() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            defer { try? KeychainStore.delete(service: service) }

            try KeychainStore.save(apiKey: "original-key-12345", service: service)
            try KeychainStore.save(apiKey: "updated-key-12345", service: service)

            let retrieved = KeychainStore.retrieve(service: service)
            XCTAssertEqual(retrieved, "updated-key-12345")
        }

        func testKeychainRetrieveReturnsNilWhenEmpty() {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            XCTAssertNil(KeychainStore.retrieve(service: service))
        }

        func testKeychainDeleteNonExistentKeyDoesNotThrow() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            XCTAssertNoThrow(try KeychainStore.delete(service: service))
        }

        func testStoreAPIKeyPublicAPI() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            defer { try? Tuteliq.removeAPIKey(service: service) }

            try Tuteliq.storeAPIKey("public-api-test-key-12345", service: service)

            let retrieved = KeychainStore.retrieve(service: service)
            XCTAssertEqual(retrieved, "public-api-test-key-12345")
        }

        func testRemoveAPIKeyPublicAPI() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"

            try Tuteliq.storeAPIKey("key-to-remove-12345", service: service)
            try Tuteliq.removeAPIKey(service: service)

            XCTAssertNil(KeychainStore.retrieve(service: service))
        }

        func testWithStoredAPIKeyThrowsWhenNoKey() {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            XCTAssertThrowsError(try Tuteliq.withStoredAPIKey(service: service)) { error in
                guard case let TuteliqError.validationError(msg, _) = error else {
                    XCTFail("Expected validationError, got \(error)")
                    return
                }
                XCTAssertTrue(msg.contains("No API key found"))
            }
        }

        func testWithStoredAPIKeyCreatesClient() throws {
            let service = "ai.tuteliq.test.\(UUID().uuidString)"
            defer { try? Tuteliq.removeAPIKey(service: service) }

            try Tuteliq.storeAPIKey("stored-api-key-12345", service: service)
            let client = try Tuteliq.withStoredAPIKey(service: service)
            XCTAssertNotNil(client)
        }

        func testConfigureFromBundleKeyThrowsWhenMissing() {
            XCTAssertThrowsError(
                try Tuteliq.configure(fromBundleKey: "NonExistentKey_\(UUID().uuidString)")
            ) { error in
                guard case let TuteliqError.validationError(msg, _) = error else {
                    XCTFail("Expected validationError, got \(error)")
                    return
                }
                XCTAssertTrue(msg.contains("No API key found in Info.plist"))
            }
        }
    #endif

    // MARK: - Verification

    func testVerificationModeEnum() {
        XCTAssertEqual(VerificationMode.age.rawValue, "age")
        XCTAssertEqual(VerificationMode.identity.rawValue, "identity")
    }

    func testDocumentTypeEnum() {
        XCTAssertEqual(DocumentType.passport.rawValue, "passport")
        XCTAssertEqual(DocumentType.nationalId.rawValue, "national_id")
        XCTAssertEqual(DocumentType.driversLicense.rawValue, "drivers_license")
    }

    func testVerificationStatusEnum() {
        XCTAssertEqual(VerificationStatus.verified.rawValue, "verified")
        XCTAssertEqual(VerificationStatus.failed.rawValue, "failed")
        XCTAssertEqual(VerificationStatus.needsReview.rawValue, "needs_review")
    }

    func testVerificationSessionStatusEnum() {
        XCTAssertEqual(VerificationSessionStatus.pending.rawValue, "pending")
        XCTAssertEqual(VerificationSessionStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(VerificationSessionStatus.documentRequired.rawValue, "document_required")
        XCTAssertEqual(VerificationSessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(VerificationSessionStatus.failed.rawValue, "failed")
        XCTAssertEqual(VerificationSessionStatus.expired.rawValue, "expired")
    }

    func testCreateVerificationSessionInput() {
        let input = CreateVerificationSessionInput(mode: .age, documentType: .passport)
        XCTAssertEqual(input.mode, .age)
        XCTAssertEqual(input.documentType, .passport)
    }

    func testVerificationSessionDecoding() throws {
        let json: [String: Any] = [
            "session_id": "vs_abc123",
            "mobile_url": "https://verify.tuteliq.ai/age/?session=vs_abc123&token=t",
            "expires_at": Int64(1_760_000_000_000),
            "mode": "age",
            "verification_mode": "full",
            "recommended_image_width": 1600,
        ]
        let session = try JSONDecoder().decode(VerificationSession.self, from: jsonData(json))

        XCTAssertEqual(session.sessionId, "vs_abc123")
        XCTAssertEqual(session.url, "https://verify.tuteliq.ai/age/?session=vs_abc123&token=t")
        XCTAssertEqual(session.mode, .age)
        XCTAssertEqual(session.expiresAt, 1_760_000_000_000)
        XCTAssertEqual(session.expiresAtDate, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(session.recommendedImageWidth, 1600)
    }

    func testVerificationSessionResultDecodingWithResult() throws {
        let json: [String: Any] = [
            "session_id": "vs_abc123",
            "status": "completed",
            "step_progress": "done",
            "created_at": Int64(1_760_000_000_000),
            "expires_at": Int64(1_760_001_800_000),
            "result": [
                "status": "verified",
                "age": 24,
                "is_minor": false,
                "date_of_birth": "2002-01-15",
                "face_match": ["matched": true, "confidence": 0.95],
                "liveness": ["valid": true],
                "failure_reasons": [] as [String],
                "document": [
                    "ocr_confidence": 92,
                    "first_name": "Anna",
                    "last_name": "Lindgren",
                    "document_type": "passport",
                    "country_code": "SE",
                    "national_id": ["value": "200201151234", "valid": true, "type": "personnummer", "country_code": "SE"],
                ],
            ],
        ]
        let result = try JSONDecoder().decode(VerificationSessionResult.self, from: jsonData(json))

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.createdAt, 1_760_000_000_000)
        XCTAssertEqual(result.result?.status, .verified)
        XCTAssertEqual(result.result?.age, 24)
        XCTAssertEqual(result.result?.faceMatch?.matched, true)
        XCTAssertNil(result.result?.faceMatch?.distance)
        XCTAssertEqual(result.result?.document?.firstName, "Anna")
        XCTAssertEqual(result.result?.document?.nationalId?.type, "personnummer")
    }

    func testSuccessfulCreateVerificationSession() async throws {
        var body: [String: Any] = [:]
        var capturedRequest: URLRequest?
        let client = try makeClient { request in
            capturedRequest = request
            if let data = request.httpBodyStream.map(Self.readAll) ?? request.httpBody {
                body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
            return self.mockResponse(statusCode: 201, json: [
                "session_id": "vs_test123",
                "mobile_url": "https://verify.tuteliq.ai/age/?session=vs_test123&token=t",
                "expires_at": Int64(1_760_000_000_000),
                "mode": "age",
            ])
        }

        let session = try await client.createVerificationSession(
            CreateVerificationSessionInput(mode: .age, documentType: .nationalId)
        )

        XCTAssertEqual(session.sessionId, "vs_test123")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(body["document_type"] as? String, "national_id")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/api/v1/verify/session") ?? false)
    }

    func testCancelVerificationSessionDecodesOk() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return self.mockResponse(json: ["ok": true])
        }
        let result = try await client.cancelVerificationSession(id: "vs_1")
        XCTAssertTrue(result.ok)
    }

    func testSuccessfulGetAgeVerification() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "verification_id": "vrf_123",
                "status": "verified",
                "is_minor": false,
                "face_matched": true,
                "liveness_valid": true,
                "failure_reasons": [] as [String],
                "created_at": "2026-03-05T10:00:00Z",
            ])
        }

        let result = try await client.getAgeVerification(id: "vrf_123")

        XCTAssertEqual(result.verificationId, "vrf_123")
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.faceMatched, true)
        XCTAssertTrue(result.livenessValid)
    }

    func testSuccessfulGetIdentityVerification() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "verification_id": "vrf_456",
                "status": "needs_review",
                "face_matched": NSNull(),
                "face_confidence": 0.61,
                "liveness_valid": true,
                "failure_reasons": ["face_match_inconclusive"],
                "created_at": "2026-03-05T10:00:00Z",
            ])
        }

        let result = try await client.getIdentityVerification(id: "vrf_456")

        XCTAssertEqual(result.status, .needsReview)
        XCTAssertNil(result.faceMatched)
        XCTAssertEqual(result.faceConfidence, 0.61)
        XCTAssertEqual(result.failureReasons, ["face_match_inconclusive"])
    }

    static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buf, maxLength: 4096)
            guard count > 0 else { break }
            data.append(buf, count: count)
        }
        return data
    }
}
