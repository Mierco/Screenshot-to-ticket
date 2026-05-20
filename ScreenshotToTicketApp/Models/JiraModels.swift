import Foundation

struct JiraVersion: Decodable, Identifiable {
    let id: String
    let name: String
    let released: Bool?
    let archived: Bool?
}

struct JiraProject: Decodable, Identifiable {
    let id: String
    let key: String
    let name: String
}

struct JiraProjectSearchResponse: Decodable {
    let values: [JiraProject]
}

struct JiraProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var projectKey: String
    var defaultFieldsJSON: String

    init(
        id: String = UUID().uuidString,
        name: String,
        projectKey: String,
        defaultFieldsJSON: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.projectKey = projectKey
        self.defaultFieldsJSON = defaultFieldsJSON
    }
}

struct JiraMyself: Decodable {
    let accountId: String
    let displayName: String
    let emailAddress: String?
}

struct JiraIssueResponse: Decodable {
    let id: String
    let key: String
    let `self`: String
}

struct JiraIssueType: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let subtask: Bool?
}

struct JiraCreateIssueTypesResponse: Decodable {
    let issueTypes: [JiraIssueType]
    let startAt: Int?
    let maxResults: Int?
    let total: Int?
}

struct JiraCreateFieldsResponse: Decodable {
    let fields: [JiraCreateFieldMetadata]
    let startAt: Int?
    let maxResults: Int?
    let total: Int?
}

struct JiraCreateFieldMetadata: Decodable, Identifiable {
    let fieldId: String
    let key: String?
    let name: String
    let required: Bool
    let hasDefaultValue: Bool?
    let operations: [String]?
    let schema: JiraFieldSchema?
    let allowedValues: [JiraFieldAllowedValue]?

    var id: String { fieldId }

    private enum CodingKeys: String, CodingKey {
        case fieldId
        case key
        case name
        case required
        case hasDefaultValue
        case operations
        case schema
        case allowedValues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decodeIfPresent(String.self, forKey: .key)
        let name = try container.decodeIfPresent(String.self, forKey: .name)

        self.key = key
        self.name = name ?? key ?? "Unknown Field"
        fieldId = try container.decodeIfPresent(String.self, forKey: .fieldId) ?? key ?? self.name
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        hasDefaultValue = try container.decodeIfPresent(Bool.self, forKey: .hasDefaultValue)
        operations = try container.decodeIfPresent([String].self, forKey: .operations)
        schema = try container.decodeIfPresent(JiraFieldSchema.self, forKey: .schema)
        allowedValues = try container.decodeIfPresent([JiraFieldAllowedValue].self, forKey: .allowedValues)
    }
}

struct JiraFieldSchema: Decodable {
    let type: String?
    let items: String?
    let system: String?
    let custom: String?
    let customId: Int?
}

struct JiraFieldAllowedValue: Decodable {
    let id: String?
    let key: String?
    let name: String?
    let value: String?
    let accountId: String?
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case name
        case value
        case accountId
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyStringIfPresent(forKey: .id)
        key = container.decodeLossyStringIfPresent(forKey: .key)
        name = container.decodeLossyStringIfPresent(forKey: .name)
        value = container.decodeLossyStringIfPresent(forKey: .value)
        accountId = container.decodeLossyStringIfPresent(forKey: .accountId)
        displayName = container.decodeLossyStringIfPresent(forKey: .displayName)
    }

    var label: String? {
        name ?? value ?? displayName ?? key ?? id
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct JiraAttachmentMetadata: Decodable {
    let id: String
    let filename: String
    let mimeType: String?
    let content: String?
    let thumbnail: String?
}

struct TicketDraft {
    let summary: String
    let description: String
}
