import Foundation

/// Which checks a session runs, from `GET /verify/session/:id/mode`.
public enum SessionVerificationMode: String, Codable, Sendable {
    /// Document + liveness + selfie.
    case full
    /// Liveness + selfie only (age estimation). The server can fall back to a document.
    case livenessOnly = "liveness_only"
}

/// How a passport or ID card chip read counts as document evidence. Chosen on
/// your backend when the session is created; the server enforces it.
public enum ChipPolicy: String, Codable, Sendable, CaseIterable {
    /// The document photo is required; a chip read adds to it. The default.
    case optional
    /// The document photo and a chip read that proves itself genuine are both required.
    case required
    /// A chip read that proves itself genuine replaces the document photo;
    /// otherwise the session asks for a photo.
    case insteadOfPhoto = "instead_of_photo"
}

/// Session configuration resolved for this end user.
public struct SessionModeInfo: Codable, Sendable, Equatable {
    public let verificationMode: SessionVerificationMode
    /// UI language the server suggests (BCP-47).
    public let lang: String?
    public let country: String?
    public let region: String?
    public let market: String?
    public let ageThreshold: Int?
    public let recommendedImageWidth: Int?
    /// How a chip read counts for this session. `nil` when the server doesn't say,
    /// which means ``ChipPolicy/optional``.
    public let chipPolicy: ChipPolicy?

    public init(
        verificationMode: SessionVerificationMode,
        lang: String? = nil,
        country: String? = nil,
        region: String? = nil,
        market: String? = nil,
        ageThreshold: Int? = nil,
        recommendedImageWidth: Int? = nil,
        chipPolicy: ChipPolicy? = nil
    ) {
        self.verificationMode = verificationMode
        self.lang = lang
        self.country = country
        self.region = region
        self.market = market
        self.ageThreshold = ageThreshold
        self.recommendedImageWidth = recommendedImageWidth
        self.chipPolicy = chipPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verificationMode = try container.decode(SessionVerificationMode.self, forKey: .verificationMode)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        market = try container.decodeIfPresent(String.self, forKey: .market)
        ageThreshold = try container.decodeIfPresent(Int.self, forKey: .ageThreshold)
        recommendedImageWidth = try container.decodeIfPresent(Int.self, forKey: .recommendedImageWidth)
        // A policy this version doesn't know must not break the flow for an app already in users' hands.
        chipPolicy = container.decodeLenient(ChipPolicy.self, forKey: .chipPolicy)
    }

    enum CodingKeys: String, CodingKey {
        case verificationMode = "verification_mode"
        case lang, country, region, market
        case ageThreshold = "age_threshold"
        case recommendedImageWidth = "recommended_image_width"
        case chipPolicy = "chip_policy"
    }
}

extension KeyedDecodingContainer {
    /// The value, or `nil` when it is missing or this version can't decode it.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// A challenge for the document's chip to sign (Active Authentication), from
/// `GET /verify/session/:id/chip-challenge`. Single use, valid for a short time:
/// fetch it just before reading the chip.
public struct ChipChallenge: Decodable, Sendable, Equatable {
    /// The bytes to send to the chip, exactly as they are.
    public let challenge: Data
    public let expiresAt: Date

    public init(challenge: Data, expiresAt: Date) {
        self.challenge = challenge
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try container.decode(String.self, forKey: .challenge)
        guard let bytes = Data(hex: hex), !bytes.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .challenge, in: container, debugDescription: "Not a hex challenge")
        }
        challenge = bytes
        expiresAt = try Date(timeIntervalSince1970: container.decode(Double.self, forKey: .expiresAt) / 1000)
    }

    enum CodingKeys: String, CodingKey {
        case challenge
        case expiresAt = "expires_at"
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

/// Side of an identity document.
public enum DocumentSide: String, Sendable, Codable {
    case front
    case back
    /// A passport's photo page (one side).
    case passport
}

/// How a document image was obtained. Camera captures get extra server checks (e.g. tilt frames).
public enum DocumentCaptureSource: String, Sendable, Codable {
    case camera
    case file
}

/// Steps reported to `POST /verify/session/:id/progress`, which drives the
/// integrator's live status (SSE / dashboard).
public enum VerificationProgressStep: String, Sendable {
    case connected
    case documentFront = "document_front"
    case documentBack = "document_back"
    case documentFrontValidated = "document_front_validated"
    case documentBackValidated = "document_back_validated"
    case documentChip = "document_chip"
    case liveness
    case livenessDone = "liveness_done"
    case selfie
    case selfieValidated = "selfie_validated"
    case submitting
}

/// Result of `validate-document`.
public struct DocumentValidationResult: Codable, Sendable, Equatable {
    public let valid: Bool
    /// `good`, `poor` (warning only) or `invalid`.
    public let quality: String
    public let issues: [String]
    /// The server processed and kept the document, so submit doesn't need the image.
    public let retained: Bool

    public init(valid: Bool, quality: String, issues: [String], retained: Bool) {
        self.valid = valid
        self.quality = quality
        self.issues = issues
        self.retained = retained
    }
}

/// Result of `validate-selfie`.
public struct SelfieValidationResult: Codable, Sendable, Equatable {
    public let valid: Bool
    public let faceDetected: Bool
    public let message: String?
    /// The server assessed liveness and the face match already, so submit needs no selfie.
    public let assessed: Bool

    public init(valid: Bool, faceDetected: Bool, message: String?, assessed: Bool) {
        self.valid = valid
        self.faceDetected = faceDetected
        self.message = message
        self.assessed = assessed
    }

    enum CodingKeys: String, CodingKey {
        case valid
        case faceDetected = "face_detected"
        case message, assessed
    }
}

/// Result of `validate-chip`.
public struct ChipValidationResult: Codable, Sendable, Equatable {
    public let valid: Bool
    public let issues: [String]
    /// The server verified and kept the chip data for this session.
    public let retained: Bool
    /// The chip read can stand in for the photographed document: it proved
    /// itself genuine and original. `nil` from a server that doesn't say.
    public let usableAsDocument: Bool?

    public init(valid: Bool, issues: [String], retained: Bool, usableAsDocument: Bool? = nil) {
        self.valid = valid
        self.issues = issues
        self.retained = retained
        self.usableAsDocument = usableAsDocument
    }

    enum CodingKeys: String, CodingKey {
        case valid, issues, retained
        case usableAsDocument = "usable_as_document"
    }
}

/// Final session state after submit.
public enum SessionSubmitStatus: String, Codable, Sendable {
    case completed
    case failed
    /// The session needs more document evidence: the user must add it and resubmit.
    /// ``SessionSubmitResult/reason`` says what is missing.
    case documentRequired = "document_required"
}

/// Why submit answered ``SessionSubmitStatus/documentRequired``, when the chip policy caused it.
public enum SessionSubmitReason: String, Codable, Sendable {
    /// The chip read can't stand in for the document: add a document photo.
    case chipNotUsable = "chip_not_usable"
    /// The session requires a chip read that proves itself genuine, and there is none yet.
    case chipRequired = "chip_required"
}

/// Result of `submit`.
public struct SessionSubmitResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let status: SessionSubmitStatus
    /// With ``SessionSubmitStatus/documentRequired``: why, when the chip policy caused it.
    /// `nil` otherwise, including when liveness alone couldn't decide.
    public let reason: SessionSubmitReason?

    public init(ok: Bool, status: SessionSubmitStatus, reason: SessionSubmitReason? = nil) {
        self.ok = ok
        self.status = status
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decode(SessionSubmitStatus.self, forKey: .status)
        reason = container.decodeLenient(SessionSubmitReason.self, forKey: .reason)
    }

    enum CodingKeys: String, CodingKey {
        case ok, status, reason
    }
}

/// A finished liveness sequence, ready to send.
public struct LivenessCapture: Sendable, Equatable {
    /// JSON liveness token (stringified), bound to the server's challenge.
    public let token: String
    /// JPEG frames in capture order, unmirrored.
    public let frames: [Data]
    /// Nonce of the challenge this capture answers.
    public let nonce: String
    /// What the TrueDepth camera measured during the challenge, when the device has one.
    public let depth: LivenessDepthEvidence?
    /// What each frame in ``frames`` shows, in the same order. Empty when unknown.
    public let frameKinds: [LivenessFrameKind]

    public init(token: String, frames: [Data], nonce: String, depth: LivenessDepthEvidence? = nil, frameKinds: [LivenessFrameKind] = []) {
        self.token = token
        self.frames = frames
        self.nonce = nonce
        self.depth = depth
        self.frameKinds = frameKinds.count == frames.count ? frameKinds : []
    }

    /// The frames with what each one shows.
    public var labeledFrames: [(kind: LivenessFrameKind?, image: Data)] {
        frames.enumerated().map { (frameKinds.indices.contains($0.offset) ? frameKinds[$0.offset] : nil, $0.element) }
    }
}

/// The token carries the signed challenge: nothing that prints or dumps a capture shows it.
extension LivenessCapture: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "LivenessCapture(nonce: \(nonce), frames: \(frames.count), frameKinds: \(frameKinds.map(\.rawValue)), depth: \(depth.map { $0.verdict.rawValue } ?? "none"), token: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["nonce": nonce, "frames": frames.count, "frameKinds": frameKinds, "depth": depth as Any, "token": "<redacted>"], displayStyle: .struct)
    }
}

/// What a liveness frame shows: the moment of the challenge it was kept for.
public enum LivenessFrameKind: String, Codable, Sendable, CaseIterable {
    /// Looking at the camera.
    case center
    /// Turned to the user's left / right.
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    /// Eyes closed during the blink, and open again after it.
    case blinkClosed = "blink_closed"
    case blinkOpen = "blink_open"
    case smile
    /// Back to facing the camera between prompts.
    case neutral
}
