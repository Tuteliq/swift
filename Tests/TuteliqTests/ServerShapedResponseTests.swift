@testable import Tuteliq
import XCTest

/// Responses shaped like the ones the API actually sends: captured from the API's
/// own route handlers, or built from the types it serializes. A model that
/// doesn't decode its own endpoint's response throws on every call in production.
final class ServerShapedResponseTests: XCTestCase {
    private var calls = 0

    private func client(maxRetries: Int = 3, cacheTTL: TimeInterval = 0, status: Int = 200, body: @escaping () -> String) throws -> Tuteliq {
        calls = 0
        MockURLProtocol.requestHandler = { [unowned self] _ in
            calls += 1
            let response = HTTPURLResponse(url: URL(string: "https://api.tuteliq.ai")!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(body().utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return try Tuteliq(apiKey: "test-api-key-12345", maxRetries: maxRetries, retryDelay: 0, cacheTTL: cacheTTL, session: URLSession(configuration: config))
    }

    private let png = DetectSyntheticMediaInput(file: Data([0x89, 0x50, 0x4E, 0x47]), filename: "photo.png")

    // MARK: - Synthetic content

    func testSyntheticImageDecodes() async throws {
        let result = try await client { Fixture.syntheticImage }.detectSyntheticImage(png)
        XCTAssertEqual(result.classification, .suspectedSynthetic)
        XCTAssertTrue(result.vision.isLikelySynthetic)
        XCTAssertEqual(result.vision.artifacts.count, 2)
        XCTAssertEqual(result.metadataAnalysis.dimensions.width, 1024)
        XCTAssertEqual(result.forensicSignals.signalCount, 5)
    }

    func testSyntheticVideoDecodes() async throws {
        let video = DetectSyntheticMediaInput(file: Data([0, 0, 0, 0x18]), filename: "clip.mp4")
        let result = try await client { Fixture.syntheticVideo }.detectSyntheticVideo(video)
        XCTAssertEqual(result.temporalConsistency?.score, 0.94)
        XCTAssertEqual(result.temporalConsistency?.identityConsistency, 0.95)
        XCTAssertEqual(result.temporalConsistency?.framesWithFaces, 2)
        XCTAssertEqual(result.temporalConsistency?.anomalousPairs.count, 0)
        XCTAssertEqual(result.lipSync?.correlation, 0.65)
        XCTAssertEqual(result.transcription?.text, "This is a test video recording.")
        XCTAssertEqual(result.transcription?.segments.count, 0)
    }

    func testSyntheticAudioWithoutSpeechDecodes() async throws {
        let audio = DetectSyntheticMediaInput(file: Data([0x49, 0x44, 0x33]), filename: "clip.mp3")
        let result = try await client { Fixture.syntheticAudioSilent }.detectSyntheticAudio(audio)
        XCTAssertEqual(result.transcription?.text, "")
        XCTAssertEqual(result.transcription?.segments.count, 0)
    }

    // MARK: - Detection

    func testAnalyseMultiDecodes() async throws {
        let input = AnalyseMultiInput(content: "test message", detections: [.bullying, .unsafe])
        let result = try await client { Fixture.analyseMulti }.analyseMulti(input)
        XCTAssertEqual(result.results.count, 10)
        // Not every detector reports a confidence inside a multi result.
        XCTAssertNil(result.results.first { $0.endpoint == "social-engineering" }?.confidence)
        XCTAssertEqual(result.results.first { $0.endpoint == "bullying" }?.confidence, 0.9)
    }

    func testAnExtendedDetectorResponseWithoutALanguageDecodes() async throws {
        let result = try await client { Fixture.socialEngineeringWithoutLanguage }.detectSocialEngineering(DetectionInput(content: "test message"))
        XCTAssertNil(result.language)
        XCTAssertNil(result.languageStatus)
    }

    // MARK: - Account

    func testPricingDecodes() async throws {
        let result = try await client { Fixture.pricing }.getPricing()
        XCTAssertEqual(result.plans.first?.isPopular, true)
        XCTAssertEqual(result.plans.first?.ctaLink, "https://example.com/signup")
    }

    func testConsentStatusDecodes() async throws {
        let result = try await client { Fixture.consents }.getConsentStatus()
        XCTAssertEqual(result.consents.first?.userId, "user_123")
        XCTAssertEqual(result.consents.first?.consentType, "data_processing")
    }

    func testAuditLogsDecode() async throws {
        let result = try await client { Fixture.auditLogs }.getAuditLogs()
        XCTAssertEqual(result.auditLogs.first?.userId, "user_123")
        XCTAssertEqual(result.auditLogs.first?.action, "data_export")
    }

    func testASnakeCaseUserIdStillDecodes() async throws {
        let body = Fixture.consents.replacingOccurrences(of: "\"userId\"", with: "\"user_id\"")
        let result = try await client { body }.getConsentStatus()
        XCTAssertEqual(result.consents.first?.userId, "user_123")
    }
}

private enum Fixture {
    static let syntheticImage = #"{"endpoint":"synthetic-content","detected":true,"severity":0.2,"level":"low","classification":"suspected_synthetic","categories":[{"tag":"AI_GENERATED_IMAGE","label":"AI-Generated Image","confidence":0.6}],"evidence":[],"recommended_action":"none","rationale":"Forensic analysis found AI-generation artifacts including unnatural skin texture.","confidence":0.6,"risk_score":0,"detected_language":"en","processing_time_ms":150,"input_type":"image","semantic_analysis":{"is_likely_synthetic":true,"synthetic_confidence":0.75,"artifacts":["Unnaturally smooth skin without pores","Perfect facial symmetry"],"face_analysis":"Unnaturally uniform skin texture, perfect bilateral symmetry","overall_assessment":"Image shows multiple indicators of AI generation."},"metadata_analysis":{"format":"jpeg","dimensions":{"width":1024,"height":768},"has_exif":true,"has_camera":false,"has_gps":false,"ai_generator_detected":false,"suspicious_absence":false},"forensic_signals":{"signal_count":5,"sources":[{"name":"semantic_analysis","signal_count":2,"confidence_boost":0.22499999999999998,"weight":0.15},{"name":"metadata","signal_count":0,"confidence_boost":0,"weight":0.15},{"name":"pixel_stats","signal_count":0,"confidence_boost":0,"weight":0.15},{"name":"provenance","signal_count":0,"confidence_boost":0,"weight":0.15},{"name":"watermark","signal_count":0,"confidence_boost":0,"weight":0.1},{"name":"perceptual_hash","signal_count":0,"confidence_boost":0,"weight":0.1},{"name":"generator_attribution","signal_count":0,"confidence_boost":0,"weight":0.12},{"name":"noise_residual","signal_count":1,"confidence_boost":0.15,"weight":0.12},{"name":"gan_frequency","signal_count":2,"confidence_boost":0.2,"weight":0.12}],"combined_confidence_boost":0.12418032786885244,"confidence_waterfall":[{"module":"semantic_analysis","signal_count":2,"confidence_boost":0.225,"weight":0.15,"weighted_contribution":0.034,"rank":1},{"module":"gan_frequency","signal_count":2,"confidence_boost":0.2,"weight":0.12,"weighted_contribution":0.024,"rank":2},{"module":"noise_residual","signal_count":1,"confidence_boost":0.15,"weight":0.12,"weighted_contribution":0.018,"rank":3},{"module":"metadata","signal_count":0,"confidence_boost":0,"weight":0.15,"weighted_contribution":0,"rank":4},{"module":"pixel_stats","signal_count":0,"confidence_boost":0,"weight":0.15,"weighted_contribution":0,"rank":5},{"module":"provenance","signal_count":0,"confidence_boost":0,"weight":0.15,"weighted_contribution":0,"rank":6},{"module":"watermark","signal_count":0,"confidence_boost":0,"weight":0.1,"weighted_contribution":0,"rank":7},{"module":"perceptual_hash","signal_count":0,"confidence_boost":0,"weight":0.1,"weighted_contribution":0,"rank":8},{"module":"generator_attribution","signal_count":0,"confidence_boost":0,"weight":0.12,"weighted_contribution":0,"rank":9}],"module_disagreements":[],"decision_basis":"3/9 modules indicate synthetic content with no contradicting signals"},"codec_analysis":{"codec":"jpeg","estimated_quality":90,"quality_bucket":"high"},"perceptual_hash":"abcd1234abcd1234","language":"en","language_status":"stable","credits_used":5}"#
    static let syntheticVideo = #"{"endpoint":"synthetic-content","detected":false,"severity":0,"level":"none","classification":"confirmed_authentic","categories":[],"evidence":[],"recommended_action":"none","rationale":"Video shows consistent face geometry and natural speech patterns.","confidence":0.15,"risk_score":0,"detected_language":"en","processing_time_ms":150,"input_type":"video","video":{"duration_seconds":5,"frames_analyzed":2,"has_audio":true},"temporal_consistency":{"score":0.94,"identity_consistency":0.95,"landmark_stability":0.92,"frames_with_faces":2,"anomalous_pairs":[]},"lip_sync":{"correlation":0.65,"has_silent_mouth_movement":false,"has_voice_without_movement":false},"audio_stats":{"rms_level":-20,"rms_peak":-10,"dc_offset":0.001,"dynamic_range":12,"silence_ratio":0.1,"peak_count":1,"flat_factor":0.1},"transcription":{"text":"This is a test video recording.","language":"en","duration":5},"language":"en","language_status":"stable","credits_used":10}"#
    static let syntheticAudioSilent = #"{"endpoint":"synthetic-content","detected":false,"severity":0,"level":"none","classification":"unknown","categories":[],"evidence":[],"recommended_action":"none","rationale":"Audio contained no intelligible speech to analyze.","confidence":0,"risk_score":0,"input_type":"audio","transcription":{"text":"","language":"en","duration":1.5},"audio_stats":{"rms_level":-20,"rms_peak":-10,"dc_offset":0.001,"dynamic_range":12,"silence_ratio":0.1,"peak_count":1,"flat_factor":0.1},"audio_forensics":{"metrics":{},"signals":[],"confidence_boost":0},"credits_used":4}"#
    static let analyseMulti = #"{"results":[{"endpoint":"social-engineering","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"app-fraud","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"romance-scam","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"mule-recruitment","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"gambling-harm","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"coercive-control","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"vulnerability-exploitation","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120,"cross_endpoint_modifier":1,"vulnerability_profile":{"emotional_vulnerability":0.3,"cognitive_vulnerability":0.2,"situational_vulnerability":0.3,"social_vulnerability":0.2}},{"endpoint":"radicalisation","detected":true,"severity":0.75,"level":"high","categories":[{"tag":"TEST","label":"Test Category","confidence":0.85}],"evidence":[{"text":"Test evidence","tactic":"TEST","weight":0.8}],"recommended_action":"Review content","rationale":"Test detection rationale","credits_used":1,"detected_language":"en","processing_time_ms":120},{"endpoint":"bullying","detected":true,"severity":0.8,"confidence":0.9,"risk_score":0.8,"level":"high","categories":[{"tag":"VERBAL_ABUSE","label":"Verbal Abuse","confidence":0.9}],"evidence":[],"recommended_action":"Review","rationale":"Test","credits_used":1},{"endpoint":"grooming","detected":true,"severity":0.2,"confidence":0.5,"risk_score":0.2,"level":"low","categories":[],"evidence":[],"recommended_action":"None","rationale":"Test","credits_used":1}],"summary":{"total_endpoints":10,"detected_count":10,"highest_risk":{"endpoint":"","risk_score":0},"overall_risk_level":"none","processing_time_ms":1,"total_credits_used":11,"vulnerability_modifier_applied":false,"analysis_status":"complete"}}"#
    static let socialEngineeringWithoutLanguage = #"{"endpoint":"social-engineering","detected":false,"severity":0.05,"confidence":0,"risk_score":0.05,"level":"none","categories":[],"evidence":[],"recommended_action":"none","rationale":"Safe content","credits_used":2,"processing_time_ms":0}"#
    static let pricing = #"{"plans":[{"name":"Pro","price":"$99","period":"/month","description":"For growing platforms","features":["All detectors"],"isPopular":true,"cta":"Start trial","ctaLink":"https://example.com/signup"}]}"#
    static let consents = #"{"consents":[{"id":"consent_1","userId":"user_123","consent_type":"data_processing","status":"granted","version":"1.0","ip_hash":"3f2a9c","created_at":"2026-10-01T10:00:00.000Z"}]}"#
    static let auditLogs = #"{"audit_logs":[{"id":"log_1","userId":"user_123","action":"data_export","_encrypted":false,"created_at":"2026-10-01T10:00:00.000Z"}]}"#
}
