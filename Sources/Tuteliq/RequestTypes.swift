import Foundation

// MARK: - Internal Encodable Request Types
//
// These types use JSONEncoder with .convertToSnakeCase, so property names
// are camelCase here and automatically become snake_case in the JSON output.
// This replaces the previous [String: Any] + JSONSerialization approach.

/// Bullying detection request body.
struct BullyingRequest: Encodable {
    let text: String
    var context: ContextPayload?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

/// Grooming detection request body.
struct GroomingRequest: Encodable {
    let messages: [GroomingMessagePayload]
    var context: ContextPayload?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

struct GroomingMessagePayload: Encodable {
    let senderRole: String
    let text: String
}

/// Unsafe content detection request body.
struct UnsafeRequest: Encodable {
    let text: String
    var context: ContextPayload?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

/// Emotion analysis request body.
struct EmotionsRequest: Encodable {
    let messages: [EmotionMessagePayload]
    var context: ContextPayload?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

struct EmotionMessagePayload: Encodable {
    let sender: String
    let text: String
}

/// Action plan request body.
struct ActionPlanRequest: Encodable {
    let role: String
    let situation: String
    var childAge: Int?
    var severity: String?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

/// Incident report request body.
struct ReportRequest: Encodable {
    let messages: [ReportMessagePayload]
    var meta: ReportMeta?
    var externalId: String?
    var customerId: String?
    var metadata: [String: AnyCodable]?
}

struct ReportMessagePayload: Encodable {
    let sender: String
    let text: String
}

struct ReportMeta: Encodable {
    var childAge: Int?
    var type: String?
    var conversationId: String?
    var timestampRange: [String]?
}

/// Webhook creation request body.
struct CreateWebhookRequest: Encodable {
    let name: String
    let url: String
    let events: [String]
    var headers: [String: String]?
}

/// Webhook update request body.
struct UpdateWebhookRequest: Encodable {
    var name: String?
    var url: String?
    var events: [String]?
    var isActive: Bool?
    var headers: [String: String]?
}

/// Webhook test request body.
struct TestWebhookRequest: Encodable {
    let webhookId: String
}

/// Policy update request body.
struct PolicyUpdateRequest: Encodable {
    let config: [String: AnyCodable]
}

/// Context payload shared across analysis requests.
struct ContextPayload: Encodable {
    var language: String?
    var ageGroup: String?
    var relationship: String?
    var platform: String?
    var childAge: Int?
}

/// Batch analysis request body.
struct BatchRequest: Encodable {
    let items: [BatchItemPayload]
    let parallel: Bool
}

struct BatchItemPayload: Encodable {
    let id: String
    let type: String
    let data: BatchItemData
}

struct BatchItemData: Encodable {
    var text: String?
    var messages: [[String: String]]?
    var context: ContextPayload?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text = text { try container.encode(text, forKey: .text) }
        if let messages = messages { try container.encode(messages, forKey: .messages) }
        if let context = context { try container.encode(context, forKey: .context) }
    }

    enum CodingKeys: String, CodingKey {
        case text, messages, context
    }
}
