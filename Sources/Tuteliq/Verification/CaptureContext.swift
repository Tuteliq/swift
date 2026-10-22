import Foundation

/// What captured a verification upload and which on-device checks ran, sent with
/// each session request as the `capture_context` field.
///
/// It is untrusted metadata asserted by the device: it says what evidence to
/// expect (a TrueDepth capture comes with depth evidence, a chip read with chip
/// files) and helps diagnose a failed capture. The server never decides a
/// verification on it; every verdict is made server-side from the uploads.
///
/// What it sends: the SDK's name and version, the platform, OS version and
/// hardware model (for diagnosing capture problems on specific devices), which
/// camera and on-device engines ran, and their derived results (verdicts, pass
/// rates, counts). It sends no image and no raw facial measurement: the
/// millimetre and distance values in ``LivenessDepthEvidence`` stay on the device.
///
/// A capture UI built on ``VerificationSessionAPI`` fills in what it knows. The
/// licensed Tuteliq Verification package fills in all of it.
public struct CaptureContext: Codable, Sendable, Equatable {
    public var sdk: SDKInfo
    /// The capture pipeline, e.g. `native-ios`.
    public var pipeline: String
    public var pipelineVersion: Int
    public var face: FaceCaptureInfo?
    public var document: DocumentCaptureInfo?
    public var chip: ChipReadInfo?

    public init(sdk: SDKInfo, pipeline: String, pipelineVersion: Int, face: FaceCaptureInfo? = nil, document: DocumentCaptureInfo? = nil, chip: ChipReadInfo? = nil) {
        self.sdk = sdk
        self.pipeline = pipeline
        self.pipelineVersion = pipelineVersion
        self.face = face
        self.document = document
        self.chip = chip
    }

    public struct SDKInfo: Codable, Sendable, Equatable {
        public var name: String
        public var version: String
        public var platform: String
        public var osVersion: String
        /// Hardware identifier, e.g. `iPhone16,1`.
        public var deviceModel: String

        public init(name: String, version: String, platform: String, osVersion: String, deviceModel: String) {
            self.name = name
            self.version = version
            self.platform = platform
            self.osVersion = osVersion
            self.deviceModel = deviceModel
        }
    }

    /// The liveness capture and selfie.
    public struct FaceCaptureInfo: Codable, Sendable, Equatable {
        /// `truedepth` or `front_wide`.
        public var camera: String
        /// The on-device liveness engine, e.g. `vision-landmarks`.
        public var livenessEngine: String
        public var livenessEngineVersion: Int
        /// TrueDepth evidence, when the camera has a depth sensor.
        public var depth: LivenessDepthEvidence?

        public init(camera: String, livenessEngine: String, livenessEngineVersion: Int, depth: LivenessDepthEvidence? = nil) {
            self.camera = camera
            self.livenessEngine = livenessEngine
            self.livenessEngineVersion = livenessEngineVersion
            self.depth = depth
        }
    }

    /// The document photos.
    public struct DocumentCaptureInfo: Codable, Sendable, Equatable {
        /// `back_wide`, or `file` for an uploaded image.
        public var camera: String
        /// Taken automatically once the document was steady and sharp.
        public var autoCaptured: Bool
        /// On-device document liveness checks.
        public var liveness: DocumentLivenessEvidence?

        public init(camera: String, autoCaptured: Bool, liveness: DocumentLivenessEvidence? = nil) {
            self.camera = camera
            self.autoCaptured = autoCaptured
            self.liveness = liveness
        }
    }

    /// The NFC chip read.
    public struct ChipReadInfo: Codable, Sendable, Equatable {
        /// `pace` or `bac`.
        public var accessProtocol: String
        /// `mrz` or `can`.
        public var accessKey: String
        /// The access key came from the MRZ read off the photo, not typed.
        public var accessKeyFromPhoto: Bool
        /// `passed`, `failed` or `not_performed`.
        public var chipAuthentication: String
        /// `passed`, `failed` or `not_performed`.
        public var activeAuthentication: String
        public var dataGroups: [Int]

        public init(accessProtocol: String, accessKey: String, accessKeyFromPhoto: Bool, chipAuthentication: String = "not_performed", activeAuthentication: String = "not_performed", dataGroups: [Int]) {
            self.accessProtocol = accessProtocol
            self.accessKey = accessKey
            self.accessKeyFromPhoto = accessKeyFromPhoto
            self.chipAuthentication = chipAuthentication
            self.activeAuthentication = activeAuthentication
            self.dataGroups = dataGroups
        }
    }

    /// The `capture_context` form field: compact JSON, snake_case keys.
    public func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// The result of the on-device depth check during liveness.
public struct LivenessDepthEvidence: Codable, Sendable, Equatable {
    public enum Verdict: String, Codable, Sendable {
        /// Consistent with a live face.
        case live
        /// Not consistent with a live face.
        case flat
        /// Not enough usable depth to decide.
        case inconclusive
    }

    /// `truedepth`.
    public var sensor: String
    public var verdict: Verdict
    /// Frames with a face that were measured.
    public var framesAnalyzed: Int
    /// Of those, frames with usable depth.
    public var framesWithDepth: Int
    /// Share of usable frames that passed each part of the check, 0-1.
    public var reliefPassRate: Double
    public var sizePassRate: Double
    /// Medians over the usable frames. These are measurements of a face, possibly
    /// a child's: they stay on the device (e.g. for a debug overlay) and are never
    /// encoded or sent.
    public var noseReliefMM: Double?
    public var interpupillaryMM: Double?
    public var distanceCM: Double?
    /// Share of the face covered by usable depth, 0-1.
    public var coverage: Double?

    /// What is sent: the derived result only.
    enum CodingKeys: String, CodingKey {
        case sensor, verdict, framesAnalyzed, framesWithDepth, reliefPassRate, sizePassRate, coverage
    }

    public init(sensor: String, verdict: Verdict, framesAnalyzed: Int, framesWithDepth: Int, reliefPassRate: Double, sizePassRate: Double,
                noseReliefMM: Double?, interpupillaryMM: Double?, distanceCM: Double?, coverage: Double?)
    {
        self.sensor = sensor
        self.verdict = verdict
        self.framesAnalyzed = framesAnalyzed
        self.framesWithDepth = framesWithDepth
        self.reliefPassRate = reliefPassRate
        self.sizePassRate = sizePassRate
        self.noseReliefMM = noseReliefMM
        self.interpupillaryMM = interpupillaryMM
        self.distanceCM = distanceCM
        self.coverage = coverage
    }
}

/// The result of the on-device document liveness check.
public struct DocumentLivenessEvidence: Codable, Sendable, Equatable {
    public enum Verdict: String, Codable, Sendable {
        case genuine
        case suspicious
        case inconclusive
    }

    public var verdict: Verdict
    /// Tilt range covered while capturing, in degrees.
    public var tiltRangeDegrees: Double
    /// Tilt frames captured and aligned to the document.
    public var tiltFrames: Int
    /// Scores from the individual checks, 0-1.
    public var opticalVariability: Double
    public var screenScore: Double
    public var printScore: Double
    public var reasons: [String]

    public init(verdict: Verdict, tiltRangeDegrees: Double, tiltFrames: Int, opticalVariability: Double, screenScore: Double, printScore: Double, reasons: [String]) {
        self.verdict = verdict
        self.tiltRangeDegrees = tiltRangeDegrees
        self.tiltFrames = tiltFrames
        self.opticalVariability = opticalVariability
        self.screenScore = screenScore
        self.printScore = printScore
        self.reasons = reasons
    }
}
