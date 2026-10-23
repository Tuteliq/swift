import Foundation

// MARK: - Policy Automation Rules

/// Severity levels used by policy rule conditions.
public enum RuleSeverity: String, Codable, Sendable {
    case low, medium, high, critical
}

/// Action types a policy rule can take when its conditions match.
public enum RuleActionType: String, Codable, Sendable {
    case block
    case flag
    case escalate
    case notify
    case logOnly = "log_only"
}

/// Conditions that must all match for a rule to fire.
public struct PolicyRuleConditions: Codable, Sendable {
    public var minRiskScore: Double?
    public var minSeverity: RuleSeverity?
    /// Only match these detected categories.
    public var categories: [String]?
    /// Only match these age groups.
    public var ageGroups: [String]?

    public init(
        minRiskScore: Double? = nil,
        minSeverity: RuleSeverity? = nil,
        categories: [String]? = nil,
        ageGroups: [String]? = nil
    ) {
        self.minRiskScore = minRiskScore
        self.minSeverity = minSeverity
        self.categories = categories
        self.ageGroups = ageGroups
    }

    enum CodingKeys: String, CodingKey {
        case minRiskScore = "min_risk_score"
        case minSeverity = "min_severity"
        case categories
        case ageGroups = "age_groups"
    }
}

/// Action taken when a rule's conditions match.
public struct PolicyRuleAction: Codable, Sendable {
    public var type: RuleActionType
    /// Escalation target (e.g. an email or team identifier).
    public var escalateTo: String?
    /// Notification channel (e.g. `slack`, `email`).
    public var notifyChannel: String?
    /// Message or reason attached to the action.
    public var message: String?
    /// Override the detected severity.
    public var overrideSeverity: String?

    public init(
        type: RuleActionType,
        escalateTo: String? = nil,
        notifyChannel: String? = nil,
        message: String? = nil,
        overrideSeverity: String? = nil
    ) {
        self.type = type
        self.escalateTo = escalateTo
        self.notifyChannel = notifyChannel
        self.message = message
        self.overrideSeverity = overrideSeverity
    }

    enum CodingKeys: String, CodingKey {
        case type
        case escalateTo = "escalate_to"
        case notifyChannel = "notify_channel"
        case message
        case overrideSeverity = "override_severity"
    }
}

/// A policy automation rule.
public struct PolicyRule: Codable, Sendable {
    public let id: String
    public let name: String
    public let enabled: Bool
    /// Detection endpoints this rule applies to (e.g. `"bullying"`, `"grooming"`).
    public let endpoints: [String]
    public let conditions: PolicyRuleConditions
    public let action: PolicyRuleAction
    /// Evaluation priority (lower first).
    public let priority: Int
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, endpoints, conditions, action, priority
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Input for ``Tuteliq/createPolicyRule(_:)``.
public struct CreatePolicyRuleInput: Encodable, Sendable {
    public var name: String
    public var enabled: Bool
    /// At least one detection endpoint.
    public var endpoints: [String]
    public var conditions: PolicyRuleConditions
    public var action: PolicyRuleAction
    /// Evaluation priority (>= 0, lower first).
    public var priority: Int

    public init(
        name: String,
        enabled: Bool = true,
        endpoints: [String],
        conditions: PolicyRuleConditions,
        action: PolicyRuleAction,
        priority: Int = 0
    ) {
        self.name = name
        self.enabled = enabled
        self.endpoints = endpoints
        self.conditions = conditions
        self.action = action
        self.priority = priority
    }
}

/// Input for ``Tuteliq/updatePolicyRule(id:_:)``. Only non-nil fields are sent.
public struct UpdatePolicyRuleInput: Encodable, Sendable {
    public var name: String?
    public var enabled: Bool?
    public var endpoints: [String]?
    public var conditions: PolicyRuleConditions?
    public var action: PolicyRuleAction?
    public var priority: Int?

    public init(
        name: String? = nil,
        enabled: Bool? = nil,
        endpoints: [String]? = nil,
        conditions: PolicyRuleConditions? = nil,
        action: PolicyRuleAction? = nil,
        priority: Int? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.endpoints = endpoints
        self.conditions = conditions
        self.action = action
        self.priority = priority
    }
}

/// Result of ``Tuteliq/listPolicyRules()``.
public struct ListPolicyRulesResult: Codable, Sendable {
    public let success: Bool
    public let rules: [PolicyRule]
}

/// Result wrapping a single policy rule.
public struct PolicyRuleResult: Codable, Sendable {
    public let success: Bool
    public let rule: PolicyRule
}

/// Input for ``Tuteliq/evaluatePolicyRules(_:)``: a hypothetical detection result.
public struct EvaluatePolicyRulesInput: Encodable, Sendable {
    /// Detection endpoint the result came from (e.g. `"grooming"`).
    public var endpoint: String
    public var riskScore: Double
    public var severity: RuleSeverity
    public var categories: [String]
    public var ageGroup: String?

    public init(endpoint: String, riskScore: Double, severity: RuleSeverity, categories: [String], ageGroup: String? = nil) {
        self.endpoint = endpoint
        self.riskScore = riskScore
        self.severity = severity
        self.categories = categories
        self.ageGroup = ageGroup
    }
}

/// A rule that matched during evaluation.
public struct MatchedPolicyRule: Codable, Sendable {
    public let ruleId: String
    public let ruleName: String
    public let action: String
    public let priority: Int

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case ruleName = "rule_name"
        case action, priority
    }
}

/// Outcome of a policy rule evaluation.
public struct PolicyEvaluation: Codable, Sendable {
    public let rulesEvaluated: Int
    public let rulesMatched: [MatchedPolicyRule]
    /// The winning action after priority resolution.
    public let policyAction: String
    public let policyMessage: String?
    /// ID of the rule whose action was applied.
    public let appliedRule: String?

    enum CodingKeys: String, CodingKey {
        case rulesEvaluated = "rules_evaluated"
        case rulesMatched = "rules_matched"
        case policyAction = "policy_action"
        case policyMessage = "policy_message"
        case appliedRule = "applied_rule"
    }
}

/// Result of ``Tuteliq/evaluatePolicyRules(_:)``.
public struct EvaluatePolicyRulesResult: Codable, Sendable {
    public let success: Bool
    public let evaluation: PolicyEvaluation
}

// MARK: - Detection Settings

/// Default context applied to detections when a request omits one.
public struct DetectionDefaultContext: Codable, Sendable {
    public var ageGroup: String?
    public var platform: String?
    public var country: String?

    public init(ageGroup: String? = nil, platform: String? = nil, country: String? = nil) {
        self.ageGroup = ageGroup
        self.platform = platform
        self.country = country
    }

    enum CodingKeys: String, CodingKey {
        case ageGroup = "age_group"
        case platform, country
    }
}

/// Current per-account detection settings.
public struct DetectionSettings: Codable, Sendable {
    public let enabledEndpoints: [String]?
    public let disabledEndpoints: [String]?
    public let defaultContext: DetectionDefaultContext?
    public let defaultConversationType: String?
    /// Account default for `flagProfanity` when a request omits it.
    public let defaultFlagProfanity: Bool?
    /// Account default for `flagRiskTerms` when a request omits it.
    public let defaultFlagRiskTerms: Bool?
    /// Every endpoint the API supports.
    public let availableEndpoints: [String]
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case enabledEndpoints = "enabled_endpoints"
        case disabledEndpoints = "disabled_endpoints"
        case defaultContext = "default_context"
        case defaultConversationType = "default_conversation_type"
        case defaultFlagProfanity = "default_flag_profanity"
        case defaultFlagRiskTerms = "default_flag_risk_terms"
        case availableEndpoints = "available_endpoints"
        case updatedAt = "updated_at"
    }
}

/// Input for ``Tuteliq/updateDetectionSettings(_:)``.
///
/// `enabledEndpoints` and `disabledEndpoints` are mutually exclusive. Only non-nil fields are sent.
public struct UpdateDetectionSettingsInput: Encodable, Sendable {
    public var enabledEndpoints: [String]?
    public var disabledEndpoints: [String]?
    public var defaultContext: DetectionDefaultContext?
    public var defaultFlagProfanity: Bool?
    public var defaultFlagRiskTerms: Bool?

    public init(
        enabledEndpoints: [String]? = nil,
        disabledEndpoints: [String]? = nil,
        defaultContext: DetectionDefaultContext? = nil,
        defaultFlagProfanity: Bool? = nil,
        defaultFlagRiskTerms: Bool? = nil
    ) {
        self.enabledEndpoints = enabledEndpoints
        self.disabledEndpoints = disabledEndpoints
        self.defaultContext = defaultContext
        self.defaultFlagProfanity = defaultFlagProfanity
        self.defaultFlagRiskTerms = defaultFlagRiskTerms
    }
}

/// Result of ``Tuteliq/updateDetectionSettings(_:)``.
public struct UpdateDetectionSettingsResult: Codable, Sendable {
    public let success: Bool
    public let settings: [String: AnyCodable]?
    public let message: String?
}

/// Generic `{ success, message }` acknowledgement.
public struct SuccessMessageResult: Codable, Sendable {
    public let success: Bool
    public let message: String?
}

// MARK: - Threat Intelligence (Business+)

/// Options for ``Tuteliq/getIntelligenceTrends(_:)``.
public struct IntelligenceTrendsOptions: Sendable {
    /// Window size in days (default 30, max 90).
    public var days: Int?
    public var endpoint: String?
    /// e.g. `"under_13"`, `"13_17"`.
    public var ageGroup: String?
    public var platform: String?

    public init(days: Int? = nil, endpoint: String? = nil, ageGroup: String? = nil, platform: String? = nil) {
        self.days = days
        self.endpoint = endpoint
        self.ageGroup = ageGroup
        self.platform = platform
    }
}

/// A start/end period.
public struct IntelligencePeriod: Codable, Sendable {
    public let start: String
    public let end: String
}

/// Anonymised threat intelligence trends across the Tuteliq network.
public struct IntelligenceTrendsResult: Codable, Sendable {
    public let period: IntelligencePeriod
    public let totalSignals: Int
    public let trendsByEndpoint: [[String: AnyCodable]]
    public let trendsByCategory: [[String: AnyCodable]]
    public let trendsByAgeGroup: [[String: AnyCodable]]
    public let trendsByPlatform: [[String: AnyCodable]]
    public let emergingThreats: [[String: AnyCodable]]
    public let geographicTrends: [[String: AnyCodable]]

    enum CodingKeys: String, CodingKey {
        case period
        case totalSignals = "total_signals"
        case trendsByEndpoint = "trends_by_endpoint"
        case trendsByCategory = "trends_by_category"
        case trendsByAgeGroup = "trends_by_age_group"
        case trendsByPlatform = "trends_by_platform"
        case emergingThreats = "emerging_threats"
        case geographicTrends = "geographic_trends"
    }
}

/// Emerging threats over a recent window.
public struct EmergingThreatsResult: Codable, Sendable {
    public let periodDays: Int
    public let emergingThreats: [[String: AnyCodable]]

    enum CodingKeys: String, CodingKey {
        case periodDays = "period_days"
        case emergingThreats = "emerging_threats"
    }
}

/// Weekly threat intelligence digest.
public struct WeeklyDigestResult: Codable, Sendable {
    public let generatedAt: String
    public let period: IntelligencePeriod
    /// Narrative summary of the week.
    public let summary: String
    public let totalSignals: Int
    public let topEndpoints: [[String: AnyCodable]]
    public let topCategories: [[String: AnyCodable]]
    public let emergingThreats: [[String: AnyCodable]]
    public let notableChanges: [String]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case period, summary
        case totalSignals = "total_signals"
        case topEndpoints = "top_endpoints"
        case topCategories = "top_categories"
        case emergingThreats = "emerging_threats"
        case notableChanges = "notable_changes"
    }
}

/// Anonymised global risk trends.
public struct RiskTrendsResult: Codable, Sendable {
    public let success: Bool
    public let trends: [String: AnyCodable]
}

// MARK: - Customer-Managed Encryption Keys

/// RSA-OAEP key size accepted by the API.
public enum CustomerKeyAlgorithm: String, Codable, Sendable {
    case rsaOaep2048 = "RSA-OAEP-2048"
    case rsaOaep4096 = "RSA-OAEP-4096"
}

/// Input for ``Tuteliq/registerEncryptionKey(_:)``.
public struct RegisterEncryptionKeyInput: Encodable, Sendable {
    public var algorithm: CustomerKeyAlgorithm
    /// PEM-encoded SPKI public key (`-----BEGIN PUBLIC KEY-----`). The private key never leaves your side.
    public var publicKeyPem: String

    public init(algorithm: CustomerKeyAlgorithm, publicKeyPem: String) {
        self.algorithm = algorithm
        self.publicKeyPem = publicKeyPem
    }
}

/// A registered customer encryption key.
public struct CustomerEncryptionKey: Codable, Sendable {
    public let algorithm: CustomerKeyAlgorithm
    public let publicKeyPem: String
    /// `sha256(DER(SPKI))` hex. Verify on your side to confirm integrity.
    public let keyFingerprint: String
    public let registeredAt: String
    /// Previous fingerprint when this registration was a rotation.
    public let rotatedFrom: String?

    enum CodingKeys: String, CodingKey {
        case algorithm
        case publicKeyPem = "public_key_pem"
        case keyFingerprint = "key_fingerprint"
        case registeredAt = "registered_at"
        case rotatedFrom = "rotated_from"
    }
}

/// Result of ``Tuteliq/revokeEncryptionKey()``.
public struct RevokeEncryptionKeyResult: Codable, Sendable {
    public let ok: Bool
}

// MARK: - Audit Receipts (EU AI Act Art 12)

/// Retention class for an audit receipt.
public enum RetentionClass: String, Codable, Sendable {
    case biometricHighRisk = "biometric-high-risk"
    case safetyHighRisk = "safety-high-risk"
    case limitedRisk = "limited-risk"
    case minimalRisk = "minimal-risk"
}

/// Signature over an audit receipt's canonical payload.
public struct AuditReceiptSignature: Codable, Sendable {
    /// `KMS_EC_P256_SHA256` or `HMAC_SHA256`.
    public let algorithm: String
    public let keyId: String
    /// Base64 signature bytes.
    public let signature: String
    public let signedAt: String

    enum CodingKeys: String, CodingKey {
        case algorithm
        case keyId = "key_id"
        case signature
        case signedAt = "signed_at"
    }
}

/// Model identity recorded on a receipt.
public struct AuditReceiptModel: Codable, Sendable {
    public let id: String
    public let version: String?
    public let promptTemplateVersion: String?

    enum CodingKeys: String, CodingKey {
        case id, version
        case promptTemplateVersion = "prompt_template_version"
    }
}

/// Risk category and level before or after a moderator review.
public struct RiskClassification: Codable, Sendable {
    public let riskCategory: String?
    public let riskLevel: String?

    enum CodingKeys: String, CodingKey {
        case riskCategory = "risk_category"
        case riskLevel = "risk_level"
    }
}

/// Moderator review details on a review receipt.
public struct AuditReceiptModeratorReview: Codable, Sendable {
    public let targetRequestId: String
    public let targetIncidentId: String
    public let action: String
    public let reasonCode: String
    public let moderatorExternalId: String?
    public let original: RiskClassification?
    public let revised: RiskClassification?

    enum CodingKeys: String, CodingKey {
        case targetRequestId = "target_request_id"
        case targetIncidentId = "target_incident_id"
        case action
        case reasonCode = "reason_code"
        case moderatorExternalId = "moderator_external_id"
        case original, revised
    }
}

/// Signed payload of an audit receipt. Further fields may be present per receipt type.
public struct AuditReceiptPayload: Codable, Sendable {
    public let v: Int
    public let requestId: String
    public let timestamp: String
    public let endpoint: String
    public let decision: String
    public let confidence: Double?
    public let severity: Double?
    public let deployer: String
    public let intendedUse: String?
    public let retentionClass: RetentionClass
    public let model: AuditReceiptModel?
    public let thresholdsApplied: [String: Double]?
    public let biometric: [String: AnyCodable]?
    public let moderatorReview: AuditReceiptModeratorReview?

    enum CodingKeys: String, CodingKey {
        case v
        case requestId = "request_id"
        case timestamp, endpoint, decision, confidence, severity, deployer
        case intendedUse = "intended_use"
        case retentionClass = "retention_class"
        case model
        case thresholdsApplied = "thresholds_applied"
        case biometric
        case moderatorReview = "moderator_review"
    }
}

/// A signed EU AI Act Art 12 audit receipt.
public struct AuditReceipt: Codable, Sendable {
    public let payload: AuditReceiptPayload
    public let signature: AuditReceiptSignature
    /// The exact canonical JSON the signature was computed over. Use it for out-of-band verification.
    public let canonical: String
}

// MARK: - Moderator Review (EU AI Act Art 14)

/// Moderator actions accepted by incident review.
public enum ModeratorAction: String, Codable, Sendable {
    case confirm
    case downgrade
    case escalate
    case reclassify
    case dismiss
    /// Sets `resolved` and stamps `resolved_at`.
    case resolve
    /// Returns the incident to `new`, keeping `resolved_at` as history.
    case reopen
}

/// Reason codes for a moderator review.
public enum ModeratorReasonCode: String, Codable, Sendable {
    case confirmedAccurate = "confirmed_accurate"
    case falsePositive = "false_positive"
    case outOfContext = "out_of_context"
    case insufficientSeverity = "insufficient_severity"
    case incorrectCategory = "incorrect_category"
    case requiresLawEnforcement = "requires_law_enforcement"
    case parentNotified = "parent_notified"
    case other
}

/// Input for ``Tuteliq/reviewIncident(id:_:)``.
public struct ReviewIncidentInput: Encodable, Sendable {
    public var action: ModeratorAction
    public var reasonCode: ModeratorReasonCode
    /// Free-form comment; encrypted with your registered public key when E2E is enabled.
    public var reasonComment: String?
    /// Required for `downgrade` / `escalate`, optional for `reclassify`.
    public var newRiskLevel: String?
    /// Required for `reclassify`.
    public var newRiskCategory: String?
    /// Stable per-moderator identifier. Required so the audit trail can attribute
    /// the decision; don't pass the account owner's id for every moderator.
    public var moderatorExternalId: String
    /// Defaults to `limited-risk` server-side.
    public var retentionClass: RetentionClass?

    public init(
        action: ModeratorAction,
        reasonCode: ModeratorReasonCode,
        moderatorExternalId: String,
        reasonComment: String? = nil,
        newRiskLevel: String? = nil,
        newRiskCategory: String? = nil,
        retentionClass: RetentionClass? = nil
    ) {
        self.action = action
        self.reasonCode = reasonCode
        self.moderatorExternalId = moderatorExternalId
        self.reasonComment = reasonComment
        self.newRiskLevel = newRiskLevel
        self.newRiskCategory = newRiskCategory
        self.retentionClass = retentionClass
    }
}

/// Short form of the audit receipt emitted for a review.
public struct AuditReceiptReference: Codable, Sendable {
    public let requestId: String
    public let timestamp: String
    public let signature: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case timestamp, signature
    }
}

/// Result of ``Tuteliq/reviewIncident(id:_:)``.
public struct ReviewIncidentResult: Codable, Sendable {
    public let incidentId: String
    public let original: RiskClassification
    public let revised: RiskClassification
    public let auditReceipt: AuditReceiptReference?

    enum CodingKeys: String, CodingKey {
        case incidentId = "incident_id"
        case original, revised
        case auditReceipt = "audit_receipt"
    }
}

/// Input for ``Tuteliq/batchReviewIncidents(_:)``: one review applied to up to 100 incidents.
public struct BatchReviewIncidentsInput: Encodable, Sendable {
    /// 1–100 incident IDs.
    public var incidentIds: [String]
    public var action: ModeratorAction
    public var reasonCode: ModeratorReasonCode
    public var reasonComment: String?
    public var newRiskLevel: String?
    public var newRiskCategory: String?
    /// Stable per-moderator identifier. Required, as for a single review, so
    /// the audit trail can attribute each decision.
    public var moderatorExternalId: String
    public var retentionClass: RetentionClass?

    public init(
        incidentIds: [String],
        action: ModeratorAction,
        reasonCode: ModeratorReasonCode,
        moderatorExternalId: String,
        reasonComment: String? = nil,
        newRiskLevel: String? = nil,
        newRiskCategory: String? = nil,
        retentionClass: RetentionClass? = nil
    ) {
        self.incidentIds = incidentIds
        self.action = action
        self.reasonCode = reasonCode
        self.moderatorExternalId = moderatorExternalId
        self.reasonComment = reasonComment
        self.newRiskLevel = newRiskLevel
        self.newRiskCategory = newRiskCategory
        self.retentionClass = retentionClass
    }
}

/// Per-incident outcome of a batch review.
public struct BatchReviewItemResult: Codable, Sendable {
    public let incidentId: String
    public let ok: Bool
    public let original: RiskClassification?
    public let revised: RiskClassification?
    public let auditReceipt: AuditReceiptReference?
    /// Present when `ok` is false.
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case incidentId = "incident_id"
        case ok, original, revised, error
        case auditReceipt = "audit_receipt"
    }
}

/// Result of ``Tuteliq/batchReviewIncidents(_:)``. Individual failures are non-fatal.
public struct BatchReviewIncidentsResult: Codable, Sendable {
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    /// Per-incident outcome, in input order.
    public let results: [BatchReviewItemResult]
}

// MARK: - Incidents Dashboard

/// Source modality of an incident.
public enum IncidentSource: String, Codable, Sendable {
    case text, voice, image, video
    case videoStream = "video_stream"
}

/// Moderation status of an incident.
public enum IncidentStatus: String, Codable, Sendable {
    case new, reviewed, escalated, resolved, dismissed
}

/// Filters for ``Tuteliq/listIncidents(_:)``.
public struct ListIncidentsInput: Sendable {
    /// Risk category (e.g. `"bullying"`, `"grooming"`).
    public var category: String?
    public var severity: RuleSeverity?
    public var status: IncidentStatus?
    public var source: IncidentSource?
    /// ISO 8601 inclusive lower bound on `created_at`.
    public var from: String?
    /// ISO 8601 exclusive upper bound on `created_at`.
    public var to: String?
    public var platform: String?
    public var externalId: String?
    public var customerId: String?
    /// 1–100 rows per page (default 25).
    public var limit: Int?
    /// `nextCursor` from the previous page.
    public var cursor: String?
    /// Include decrypted `summary` text per row, at an extra credit per row.
    public var includeSummary: Bool

    public init(
        category: String? = nil,
        severity: RuleSeverity? = nil,
        status: IncidentStatus? = nil,
        source: IncidentSource? = nil,
        from: String? = nil,
        to: String? = nil,
        platform: String? = nil,
        externalId: String? = nil,
        customerId: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        includeSummary: Bool = false
    ) {
        self.category = category
        self.severity = severity
        self.status = status
        self.source = source
        self.from = from
        self.to = to
        self.platform = platform
        self.externalId = externalId
        self.customerId = customerId
        self.limit = limit
        self.cursor = cursor
        self.includeSummary = includeSummary
    }
}

/// One row of an incident listing.
public struct IncidentSummaryRow: Codable, Sendable {
    public let id: String
    public let riskCategory: String
    public let riskLevel: String
    public let confidenceScore: Double?
    public let detectedPatterns: [String]
    public let platform: String?
    public let language: String?
    public let source: String
    public let fileId: String?
    public let status: String
    public let externalId: String?
    public let customerId: String?
    public let createdAt: String
    /// Decrypted text, or a BYOK envelope object. Present when `includeSummary` was requested.
    public let summary: AnyCodable?
    /// Fields that are BYOK hybrid envelopes to decrypt client-side with your RSA private key.
    public let e2eEnvelopeFields: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case riskCategory = "risk_category"
        case riskLevel = "risk_level"
        case confidenceScore = "confidence_score"
        case detectedPatterns = "detected_patterns"
        case platform, language, source
        case fileId = "file_id"
        case status
        case externalId = "external_id"
        case customerId = "customer_id"
        case createdAt = "created_at"
        case summary
        case e2eEnvelopeFields = "_e2e_envelope_fields"
    }
}

/// Result of ``Tuteliq/listIncidents(_:)``.
public struct ListIncidentsResult: Codable, Sendable {
    public let incidents: [IncidentSummaryRow]
    /// Pass back as `cursor`. `nil` when there are no more pages.
    public let nextCursor: String?
    public let totalReturned: Int

    enum CodingKeys: String, CodingKey {
        case incidents
        case nextCursor = "next_cursor"
        case totalReturned = "total_returned"
    }
}

/// Per-message trajectory on a multi-turn incident.
public struct IncidentMessageAnalysis: Codable, Sendable {
    public let messageIndex: Int
    public let riskScore: Double
    public let flags: [String]

    enum CodingKeys: String, CodingKey {
        case messageIndex = "message_index"
        case riskScore = "risk_score"
        case flags
    }
}

/// Full detail of a single incident.
public struct IncidentDetail: Codable, Sendable {
    public let id: String
    public let riskCategory: String
    public let riskLevel: String
    public let confidenceScore: Double?
    public let detectedPatterns: [String]
    public let platform: String?
    public let language: String?
    public let source: String
    public let fileId: String?
    public let status: String
    public let externalId: String?
    public let customerId: String?
    public let createdAt: String
    /// Decrypted text, or a BYOK envelope object (see `e2eEnvelopeFields`).
    public let summary: AnyCodable?
    public let metadata: AnyCodable?
    public let sourceData: [String: AnyCodable]?
    public let visualCategories: [String]?
    public let visualSeverity: String?
    public let visualConfidence: Double?
    public let containsText: Bool?
    public let containsFaces: Bool?
    public let recommendedActions: [String]?
    public let emotionalIndicators: [String]?
    public let review: [String: AnyCodable]?
    public let messageAnalysis: [IncidentMessageAnalysis]?
    public let e2eEnvelopeFields: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case riskCategory = "risk_category"
        case riskLevel = "risk_level"
        case confidenceScore = "confidence_score"
        case detectedPatterns = "detected_patterns"
        case platform, language, source
        case fileId = "file_id"
        case status
        case externalId = "external_id"
        case customerId = "customer_id"
        case createdAt = "created_at"
        case summary, metadata
        case sourceData = "source_data"
        case visualCategories = "visual_categories"
        case visualSeverity = "visual_severity"
        case visualConfidence = "visual_confidence"
        case containsText = "contains_text"
        case containsFaces = "contains_faces"
        case recommendedActions = "recommended_actions"
        case emotionalIndicators = "emotional_indicators"
        case review
        case messageAnalysis = "message_analysis"
        case e2eEnvelopeFields = "_e2e_envelope_fields"
    }
}

/// An ISO 8601 time window.
public struct IncidentTimeframe: Codable, Sendable {
    public let from: String
    public let to: String
}

/// Incident count for one platform.
public struct PlatformCount: Codable, Sendable {
    public let platform: String
    public let count: Int
}

/// KPI overview from ``Tuteliq/getIncidentsOverview(from:to:)``.
public struct IncidentsOverview: Codable, Sendable {
    public let timeframe: IncidentTimeframe
    public let totalIncidents: Int
    /// High/critical incidents not yet triaged (status `new`): the actionable triage queue.
    public let requiresReviewCount: Int
    public let last24hCount: Int
    public let last7dCount: Int
    public let last30dCount: Int
    public let countsByCategory: [String: Int]
    public let countsBySeverity: [String: Int]
    public let countsBySource: [String: Int]
    public let countsByStatus: [String: Int]
    /// Top 5 platforms by incident count.
    public let topPlatforms: [PlatformCount]

    enum CodingKeys: String, CodingKey {
        case timeframe
        case totalIncidents = "total_incidents"
        case requiresReviewCount = "requires_review_count"
        case last24hCount = "last_24h_count"
        case last7dCount = "last_7d_count"
        case last30dCount = "last_30d_count"
        case countsByCategory = "counts_by_category"
        case countsBySeverity = "counts_by_severity"
        case countsBySource = "counts_by_source"
        case countsByStatus = "counts_by_status"
        case topPlatforms = "top_platforms"
    }
}

/// Bucket size for incident trends.
public enum IncidentTrendBucketSize: String, Codable, Sendable {
    case hour, day, week
}

/// One time bucket of incident counts.
public struct IncidentTrendsBucket: Codable, Sendable {
    public let bucketStart: String
    public let total: Int
    public let bySeverity: [String: Int]

    enum CodingKeys: String, CodingKey {
        case bucketStart = "bucket_start"
        case total
        case bySeverity = "by_severity"
    }
}

/// Time-bucketed incident counts from ``Tuteliq/getIncidentTrends(bucket:from:to:)``.
public struct IncidentTrends: Codable, Sendable {
    public let bucketSize: IncidentTrendBucketSize
    public let timeframe: IncidentTimeframe
    public let series: [IncidentTrendsBucket]

    enum CodingKeys: String, CodingKey {
        case bucketSize = "bucket_size"
        case timeframe, series
    }
}
