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
