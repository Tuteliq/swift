import XCTest
@testable import SafeNest

final class SafeNestTests: XCTestCase {

    func testClientInitialization() {
        let client = SafeNest(apiKey: "test-api-key-12345")
        XCTAssertNotNil(client)
    }

    func testClientInitializationWithOptions() {
        let client = SafeNest(
            apiKey: "test-api-key-12345",
            timeout: 60,
            maxRetries: 5,
            retryDelay: 2
        )
        XCTAssertNotNil(client)
    }

    func testAnalysisContext() {
        let context = AnalysisContext(
            language: "en",
            ageGroup: "11-13",
            relationship: "classmates",
            platform: "chat"
        )
        XCTAssertEqual(context.language, "en")
        XCTAssertEqual(context.ageGroup, "11-13")
    }

    func testGroomingMessage() {
        let message = GroomingMessage(
            role: .adult,
            content: "Hello"
        )
        XCTAssertEqual(message.role, .adult)
        XCTAssertEqual(message.content, "Hello")
    }

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
    }

    func testDetectBullyingInput() {
        let input = DetectBullyingInput(
            content: "Test message",
            context: AnalysisContext(platform: "chat"),
            externalId: "msg_123",
            metadata: ["user_id": "user_456"]
        )
        XCTAssertEqual(input.content, "Test message")
        XCTAssertEqual(input.externalId, "msg_123")
    }

    func testAnalyzeInput() {
        let input = AnalyzeInput(
            content: "Test message",
            include: [.bullying, .unsafe]
        )
        XCTAssertEqual(input.content, "Test message")
        XCTAssertEqual(input.include?.count, 2)
    }
}
