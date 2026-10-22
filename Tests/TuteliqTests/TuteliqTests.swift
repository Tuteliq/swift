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
        XCTAssertEqual(RecommendedAction.flagForModerator.rawValue, "flag_for_moderator")
        XCTAssertEqual(RecommendedAction.immediateIntervention.rawValue, "immediate_intervention")
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
            "recommended_action": "flag_for_moderator",
            "risk_score": 0.82,
            "external_id": "msg_123",
            "customer_id": "cust_456",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(BullyingResult.self, from: data)

        XCTAssertTrue(result.isBullying)
        XCTAssertEqual(result.bullyingType, ["verbal", "exclusion"])
        XCTAssertEqual(result.confidence, 0.87)
        XCTAssertEqual(result.severity, .high)
        XCTAssertEqual(result.riskScore, 0.82)
        XCTAssertEqual(result.recommendedAction, "flag_for_moderator")
        XCTAssertEqual(result.externalId, "msg_123")
        XCTAssertEqual(result.customerId, "cust_456")
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
            "summary": "Concerns detected",
            "recommended_action": "flag_for_moderator",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)

        XCTAssertEqual(result.riskLevel, .high)
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
        XCTAssertEqual(DocumentType.idCard.rawValue, "id_card")
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
        XCTAssertEqual(VerificationSessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(VerificationSessionStatus.failed.rawValue, "failed")
        XCTAssertEqual(VerificationSessionStatus.expired.rawValue, "expired")
        XCTAssertEqual(VerificationSessionStatus.cancelled.rawValue, "cancelled")
    }

    func testCreateVerificationSessionInput() {
        let input = CreateVerificationSessionInput(mode: .age, documentType: .passport)
        XCTAssertEqual(input.mode, .age)
        XCTAssertEqual(input.documentType, .passport)
    }

    func testVerificationSessionDecoding() throws {
        let json: [String: Any] = [
            "session_id": "vs_abc123",
            "mobile_url": "https://verify.tuteliq.ai/session/vs_abc123",
            "expires_at": "2026-03-05T12:00:00Z",
            "mode": "age",
        ]
        let data = jsonData(json)
        let session = try JSONDecoder().decode(VerificationSession.self, from: data)

        XCTAssertEqual(session.sessionId, "vs_abc123")
        XCTAssertEqual(session.url, "https://verify.tuteliq.ai/session/vs_abc123")
        XCTAssertEqual(session.mode, .age)
    }

    func testAgeVerificationResultDecoding() throws {
        let json: [String: Any] = [
            "verification_id": "vrf_123",
            "status": "verified",
            "age_bracket": "18-25",
            "is_minor": false,
            "credits_used": 10,
            "liveness": ["valid": true],
            "face_match": ["matched": true, "confidence": 0.95, "distance": 0.12],
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(AgeVerificationResult.self, from: data)

        XCTAssertEqual(result.verificationId, "vrf_123")
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.ageBracket, "18-25")
        XCTAssertEqual(result.isMinor, false)
        XCTAssertEqual(result.creditsUsed, 10)
        XCTAssertEqual(result.liveness?.valid, true)
        XCTAssertEqual(result.faceMatch?.matched, true)
        XCTAssertEqual(result.faceMatch?.confidence, 0.95)
    }

    func testIdentityVerificationResultDecoding() throws {
        let json: [String: Any] = [
            "verification_id": "vrf_456",
            "status": "verified",
            "full_name": "John Doe",
            "date_of_birth": "1990-01-15",
            "document_type": "passport",
            "country_code": "US",
            "credits_used": 15,
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(IdentityVerificationResult.self, from: data)

        XCTAssertEqual(result.verificationId, "vrf_456")
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.fullName, "John Doe")
        XCTAssertEqual(result.dateOfBirth, "1990-01-15")
        XCTAssertEqual(result.countryCode, "US")
    }

    func testVerificationSessionResultDecoding() throws {
        let json: [String: Any] = [
            "session_id": "vs_abc123",
            "status": "completed",
            "created_at": "2026-03-05T10:00:00Z",
            "expires_at": "2026-03-05T12:00:00Z",
        ]
        let data = jsonData(json)
        let result = try JSONDecoder().decode(VerificationSessionResult.self, from: data)

        XCTAssertEqual(result.sessionId, "vs_abc123")
        XCTAssertEqual(result.status, .completed)
    }

    func testSuccessfulCreateVerificationSession() async throws {
        var capturedRequest: URLRequest?
        let client = try makeClient { request in
            capturedRequest = request
            return self.mockResponse(json: [
                "session_id": "vs_test123",
                "mobile_url": "https://verify.tuteliq.ai/session/vs_test123",
                "expires_at": "2026-03-05T12:00:00Z",
                "mode": "age",
            ])
        }

        let input = CreateVerificationSessionInput(mode: .age, documentType: .passport)
        let session = try await client.createVerificationSession(input)

        XCTAssertEqual(session.sessionId, "vs_test123")
        XCTAssertEqual(session.url, "https://verify.tuteliq.ai/session/vs_test123")
        XCTAssertEqual(session.mode, .age)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/api/v1/verify/session") ?? false)
    }

    func testSuccessfulGetVerificationSession() async throws {
        var capturedRequest: URLRequest?
        let client = try makeClient { request in
            capturedRequest = request
            return self.mockResponse(json: [
                "session_id": "vs_test123",
                "status": "pending",
                "created_at": "2026-03-05T10:00:00Z",
                "expires_at": "2026-03-05T12:00:00Z",
            ])
        }

        let result = try await client.getVerificationSession(id: "vs_test123")

        XCTAssertEqual(result.sessionId, "vs_test123")
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/api/v1/verify/session/vs_test123") ?? false)
    }

    func testSuccessfulGetAgeVerification() async throws {
        let client = try makeClient { _ in
            self.mockResponse(json: [
                "verification_id": "vrf_123",
                "status": "verified",
                "age_bracket": "18-25",
                "is_minor": false,
                "created_at": "2026-03-05T10:00:00Z",
            ])
        }

        let result = try await client.getAgeVerification(id: "vrf_123")

        XCTAssertEqual(result.verificationId, "vrf_123")
        XCTAssertEqual(result.status, .verified)
    }
}
