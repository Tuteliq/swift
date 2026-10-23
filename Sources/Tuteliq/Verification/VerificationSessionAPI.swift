import Foundation

/// The verification session endpoints, as used by a capture UI.
///
/// ``VerificationSessionClient`` implements it against the API. Build your own capture
/// UI on it, or pass a fake to tests. The licensed Tuteliq Verification package's
/// native flow uses this same protocol.
public protocol VerificationSessionAPI: Sendable {
    func fetchMode() async throws -> SessionModeInfo
    func reportProgress(_ step: VerificationProgressStep) async
    func fetchLivenessChallenge() async throws -> LivenessChallenge
    /// `context` describes the capture (see ``CaptureContext``); pass `nil` when unknown.
    func validateDocument(_ jpeg: Data, side: DocumentSide, documentType: DocumentType, captureSource: DocumentCaptureSource, context: CaptureContext?) async throws -> DocumentValidationResult
    /// Uploads the raw, signed files read from a document's chip. `nil` when the API
    /// doesn't offer chip validation.
    func validateChip(_ files: [ChipFile: Data], documentType: DocumentType, context: CaptureContext?) async throws -> ChipValidationResult?
    func validateSelfie(_ jpeg: Data, liveness: LivenessCapture?, context: CaptureContext?) async throws -> SelfieValidationResult
    func submit(_ submission: SessionSubmission) async throws -> SessionSubmitResult
}

extension VerificationSessionClient: VerificationSessionAPI {}

public extension VerificationSessionAPI {
    func validateDocument(_ jpeg: Data, side: DocumentSide, documentType: DocumentType, captureSource: DocumentCaptureSource) async throws -> DocumentValidationResult {
        try await validateDocument(jpeg, side: side, documentType: documentType, captureSource: captureSource, context: nil)
    }

    func validateChip(_ files: [ChipFile: Data], documentType: DocumentType) async throws -> ChipValidationResult? {
        try await validateChip(files, documentType: documentType, context: nil)
    }

    func validateSelfie(_ jpeg: Data, liveness: LivenessCapture?) async throws -> SelfieValidationResult {
        try await validateSelfie(jpeg, liveness: liveness, context: nil)
    }
}

/// Files read from an ICAO 9303 chip, keyed by their `validate-chip` field name.
/// Upload them exactly as read, without re-encoding.
public enum ChipFile: String, CaseIterable, Sendable {
    /// EF.COM (tag `60`).
    case com = "ef_com"
    /// DG1, the MRZ (tag `61`).
    case dg1
    /// DG2, the face image (tag `75`).
    case dg2
    /// DG11, additional personal details.
    case dg11
    /// DG12, additional document details.
    case dg12
    /// DG14, Chip Authentication public key info.
    case dg14
    /// DG15, Active Authentication public key.
    case dg15
    /// EF.SOD, the Document Security Object (tag `77`).
    case sod = "ef_sod"
}
