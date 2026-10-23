import Foundation

// MARK: - Synthetic Content Detection

/// Synthetic content classification levels.
public enum SyntheticClassification: String, Codable, Sendable {
    case confirmedSynthetic = "confirmed_synthetic"
    case suspectedSynthetic = "suspected_synthetic"
    case unknown
    case confirmedAuthentic = "confirmed_authentic"
}

/// Input for ``Tuteliq/detectSyntheticText(_:)``.
public struct DetectSyntheticTextInput: Sendable {
    /// Text to analyze for AI-generation indicators.
    public var content: String
    public var context: AnalysisContext?
    public var supportThreshold: SupportThreshold?
    /// Skip the verdict cache for both read and write, forcing a fresh evaluation.
    /// Cached verdicts are keyed by a SHA-256 of the input and expire after 1 hour.
    public var bypassCache: Bool
    public var externalId: String?
    public var customerId: String?
    public var metadata: [String: AnyCodable]?
    /// Per-call override of the account's incident logging; `nil` uses the account default.
    public var incidentModerationEnabled: Bool?

    public init(
        content: String,
        context: AnalysisContext? = nil,
        supportThreshold: SupportThreshold? = nil,
        bypassCache: Bool = false,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: Any]? = nil,
        incidentModerationEnabled: Bool? = nil
    ) {
        self.content = content
        self.context = context
        self.supportThreshold = supportThreshold
        self.bypassCache = bypassCache
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.incidentModerationEnabled = incidentModerationEnabled
    }
}

/// Input for the file-based synthetic detectors (image, audio, video).
public struct DetectSyntheticMediaInput: Sendable {
    /// Raw file data.
    public var file: Data
    /// Filename with extension (used for MIME type detection).
    public var filename: String
    /// Video only: maximum frames to extract (API default 6, max 20).
    public var maxFrames: Int?
    public var ageGroup: String?
    /// Language hint (ISO 639-1).
    public var language: String?
    /// Your app or product name; the SDK appends its own identifier.
    public var platform: String?
    /// Skip the verdict cache for both read and write.
    public var bypassCache: Bool
    public var externalId: String?
    public var customerId: String?
    public var metadata: [String: String]?

    public init(
        file: Data,
        filename: String,
        maxFrames: Int? = nil,
        ageGroup: String? = nil,
        language: String? = nil,
        platform: String? = nil,
        bypassCache: Bool = false,
        externalId: String? = nil,
        customerId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.file = file
        self.filename = filename
        self.maxFrames = maxFrames
        self.ageGroup = ageGroup
        self.language = language
        self.platform = platform
        self.bypassCache = bypassCache
        self.externalId = externalId
        self.customerId = customerId
        self.metadata = metadata
    }
}

/// Result from ``Tuteliq/detectSyntheticText(_:)``.
public struct SyntheticTextResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let level: String
    public let classification: SyntheticClassification
    public let confidence: Double
    public let riskScore: Double
    public let categories: [DetectionCategory]
    public let evidence: [DetectionEvidence]?
    public let ageCalibration: AgeCalibration?
    public let recommendedAction: RecommendedAction
    public let actionDetail: String?
    public let rationale: String
    public let processingTimeMs: Double?
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let support: SupportData?
    public let externalId: String?
    public let customerId: String?
    public let metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, level, classification, confidence, categories, evidence
        case riskScore = "risk_score"
        case ageCalibration = "age_calibration"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case rationale
        case processingTimeMs = "processing_time_ms"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case support
        case externalId = "external_id"
        case customerId = "customer_id"
        case metadata
    }
}

/// Vision forensic analysis of an image.
public struct SyntheticVisionResult: Codable, Sendable {
    public let isLikelySynthetic: Bool
    public let syntheticConfidence: Double
    /// Detected AI-generation artifacts.
    public let artifacts: [String]
    public let faceAnalysis: String
    public let overallAssessment: String

    enum CodingKeys: String, CodingKey {
        case isLikelySynthetic = "is_likely_synthetic"
        case syntheticConfidence = "synthetic_confidence"
        case artifacts
        case faceAnalysis = "face_analysis"
        case overallAssessment = "overall_assessment"
    }
}

/// Pixel dimensions of an image.
public struct ImageDimensions: Codable, Sendable {
    public let width: Int
    public let height: Int
}

/// EXIF / metadata analysis of an image.
public struct MetadataAnalysis: Codable, Sendable {
    public let format: String
    public let dimensions: ImageDimensions
    public let hasExif: Bool
    public let hasCamera: Bool
    public let hasGps: Bool
    public let cameraModel: String?
    public let aiGeneratorDetected: Bool
    public let aiGenerator: String?
    /// High resolution with no camera metadata.
    public let suspiciousAbsence: Bool

    enum CodingKeys: String, CodingKey {
        case format, dimensions
        case hasExif = "has_exif"
        case hasCamera = "has_camera"
        case hasGps = "has_gps"
        case cameraModel = "camera_model"
        case aiGeneratorDetected = "ai_generator_detected"
        case aiGenerator = "ai_generator"
        case suspiciousAbsence = "suspicious_absence"
    }
}

/// C2PA Content Credentials provenance.
public struct ProvenanceResult: Codable, Sendable {
    public let hasC2pa: Bool
    public let claimGenerator: String?
    public let isAiGenerated: Bool
    public let aiTool: String?

    enum CodingKeys: String, CodingKey {
        case hasC2pa = "has_c2pa"
        case claimGenerator = "claim_generator"
        case isAiGenerated = "is_ai_generated"
        case aiTool = "ai_tool"
    }
}

/// One signal source in the forensic ensemble.
public struct ForensicSignalSource: Codable, Sendable {
    public let name: String
    public let signalCount: Int
    public let confidenceBoost: Double

    enum CodingKeys: String, CodingKey {
        case name
        case signalCount = "signal_count"
        case confidenceBoost = "confidence_boost"
    }
}

/// Multi-signal forensic ensemble summary.
public struct ForensicSignals: Codable, Sendable {
    public let signalCount: Int
    public let sources: [ForensicSignalSource]
    public let combinedConfidenceBoost: Double

    enum CodingKeys: String, CodingKey {
        case signalCount = "signal_count"
        case sources
        case combinedConfidenceBoost = "combined_confidence_boost"
    }
}

/// A perceptual-hash match against known synthetic content.
public struct KnownSyntheticMatch: Codable, Sendable {
    /// Hamming distance (lower is closer).
    public let distance: Int
    public let category: String
}

/// Result from ``Tuteliq/detectSyntheticImage(_:)``.
public struct SyntheticImageResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let level: String
    public let classification: SyntheticClassification
    public let confidence: Double
    public let riskScore: Double
    public let categories: [DetectionCategory]
    public let evidence: [DetectionEvidence]?
    public let recommendedAction: RecommendedAction
    public let actionDetail: String?
    public let rationale: String
    /// The visual (semantic) analysis. Sent by the API as `semantic_analysis`.
    public let vision: SyntheticVisionResult
    public let metadataAnalysis: MetadataAnalysis
    /// Present only when a C2PA manifest is found.
    public let provenance: ProvenanceResult?
    public let forensicSignals: ForensicSignals
    /// 64-bit DCT-based perceptual hash.
    public let perceptualHash: String
    public let knownSyntheticMatch: KnownSyntheticMatch?
    public let processingTimeMs: Double?
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, level, classification, confidence, categories, evidence
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case rationale
        case vision = "semantic_analysis"
        case metadataAnalysis = "metadata_analysis"
        case provenance
        case forensicSignals = "forensic_signals"
        case perceptualHash = "perceptual_hash"
        case knownSyntheticMatch = "known_synthetic_match"
        case processingTimeMs = "processing_time_ms"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}

/// Quantitative audio statistics from spectral analysis.
public struct AudioStats: Codable, Sendable {
    public let rmsMean: Double?
    public let rmsPeak: Double?
    public let dynamicRange: Double?
    public let silenceRatio: Double?
    /// 0–1; higher means more uniform (more synthetic-looking).
    public let flatFactor: Double?
    public let dcOffset: Double?

    enum CodingKeys: String, CodingKey {
        case rmsMean = "rms_mean"
        case rmsPeak = "rms_peak"
        case dynamicRange = "dynamic_range"
        case silenceRatio = "silence_ratio"
        case flatFactor = "flat_factor"
        case dcOffset = "dc_offset"
    }
}

/// Result from ``Tuteliq/detectSyntheticAudio(_:)``.
public struct SyntheticAudioResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let level: String
    public let classification: SyntheticClassification
    public let confidence: Double
    public let riskScore: Double
    public let categories: [DetectionCategory]
    public let recommendedAction: RecommendedAction
    public let actionDetail: String?
    public let rationale: String
    public let transcription: TranscriptionResult?
    public let audioStats: AudioStats?
    public let spectralSignals: [String]?
    public let processingTimeMs: Double?
    public let language: String?
    public let languageStatus: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, level, classification, confidence, categories
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case rationale, transcription
        case audioStats = "audio_stats"
        case spectralSignals = "spectral_signals"
        case processingTimeMs = "processing_time_ms"
        case language
        case languageStatus = "language_status"
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}

/// Basic properties of an analysed video.
public struct SyntheticVideoInfo: Codable, Sendable {
    public let durationSeconds: Double
    public let framesAnalyzed: Int
    public let hasAudio: Bool

    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
        case framesAnalyzed = "frames_analyzed"
        case hasAudio = "has_audio"
    }
}

/// A pair of frames whose face identity changed anomalously.
public struct AnomalousFramePair: Codable, Sendable {
    public let frameA: Int
    public let frameB: Int
    public let distance: Double

    enum CodingKeys: String, CodingKey {
        case frameA = "frame_a"
        case frameB = "frame_b"
        case distance
    }
}

/// Temporal face consistency across video frames.
public struct TemporalConsistency: Codable, Sendable {
    /// Overall temporal consistency (0 to 1).
    public let score: Double
    public let identityConsistency: Double
    public let landmarkStability: Double
    public let framesWithFaces: Int
    public let anomalousPairs: [AnomalousFramePair]

    enum CodingKeys: String, CodingKey {
        case score
        case identityConsistency = "identity_consistency"
        case landmarkStability = "landmark_stability"
        case framesWithFaces = "frames_with_faces"
        case anomalousPairs = "anomalous_pairs"
    }
}

/// Audio-visual lip-sync correlation.
public struct LipSyncResult: Codable, Sendable {
    /// Pearson correlation between mouth openness and audio energy (-1 to 1).
    public let correlation: Double
    public let hasSilentMouthMovement: Bool
    public let hasVoiceWithoutMovement: Bool

    enum CodingKeys: String, CodingKey {
        case correlation
        case hasSilentMouthMovement = "has_silent_mouth_movement"
        case hasVoiceWithoutMovement = "has_voice_without_movement"
    }
}

/// Result from ``Tuteliq/detectSyntheticVideo(_:)``.
public struct SyntheticVideoResult: Codable, Sendable {
    public let endpoint: String
    public let detected: Bool
    public let severity: Double
    public let level: String
    public let classification: SyntheticClassification
    public let confidence: Double
    public let riskScore: Double
    public let categories: [DetectionCategory]
    public let recommendedAction: RecommendedAction
    public let actionDetail: String?
    public let rationale: String
    public let video: SyntheticVideoInfo
    public let temporalConsistency: TemporalConsistency?
    public let lipSync: LipSyncResult?
    public let transcription: TranscriptionResult?
    public let audioStats: AudioStats?
    public let spectralSignals: [String]?
    public let processingTimeMs: Double?
    public let language: String?
    public let creditsUsed: Int?
    public let externalId: String?
    public let customerId: String?

    enum CodingKeys: String, CodingKey {
        case endpoint, detected, severity, level, classification, confidence, categories
        case riskScore = "risk_score"
        case recommendedAction = "recommended_action"
        case actionDetail = "action_detail"
        case rationale, video
        case temporalConsistency = "temporal_consistency"
        case lipSync = "lip_sync"
        case transcription
        case audioStats = "audio_stats"
        case spectralSignals = "spectral_signals"
        case processingTimeMs = "processing_time_ms"
        case language
        case creditsUsed = "credits_used"
        case externalId = "external_id"
        case customerId = "customer_id"
    }
}
