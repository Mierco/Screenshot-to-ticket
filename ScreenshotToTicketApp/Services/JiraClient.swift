import Foundation

struct JiraClient {
    let workspaceURL: String
    let email: String
    let apiToken: String
    let projectKey: String

    func fetchCurrentUser() async throws -> JiraMyself {
        let endpoint = apiURL("/rest/api/3/myself")
        let request = try buildRequest(urlString: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(JiraMyself.self, from: data)
    }

    func validateProjectAccess(projectKey: String) async throws {
        let endpoint = apiURL("/rest/api/3/project/\(projectKey)")
        let request = try buildRequest(urlString: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func fetchAccessibleProjects() async throws -> [JiraProject] {
        let endpoint = apiURL("/rest/api/3/project/search?maxResults=1000")
        let request = try buildRequest(urlString: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(JiraProjectSearchResponse.self, from: data)
        return decoded.values.sorted { $0.key < $1.key }
    }

    func fetchCreateIssueTypes(projectKey: String) async throws -> [JiraIssueType] {
        var issueTypes: [JiraIssueType] = []
        var startAt = 0
        let maxResults = 50

        while true {
            let endpoint = apiURL(
                "/rest/api/3/issue/createmeta/\(pathComponent(projectKey))/issuetypes?startAt=\(startAt)&maxResults=\(maxResults)"
            )
            let request = try buildRequest(urlString: endpoint, method: "GET")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(JiraCreateIssueTypesResponse.self, from: data)
            issueTypes.append(contentsOf: decoded.issueTypes)

            let pageSize = decoded.maxResults ?? maxResults
            let total = decoded.total ?? issueTypes.count
            startAt += max(pageSize, decoded.issueTypes.count)

            if decoded.issueTypes.isEmpty || startAt >= total {
                break
            }
        }

        return issueTypes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchCreateFields(projectKey: String, issueTypeId: String) async throws -> [JiraCreateFieldMetadata] {
        var fields: [JiraCreateFieldMetadata] = []
        var startAt = 0
        let maxResults = 200

        while true {
            let endpoint = apiURL(
                "/rest/api/3/issue/createmeta/\(pathComponent(projectKey))/issuetypes/\(pathComponent(issueTypeId))?startAt=\(startAt)&maxResults=\(maxResults)"
            )
            let request = try buildRequest(urlString: endpoint, method: "GET")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(JiraCreateFieldsResponse.self, from: data)
            fields.append(contentsOf: decoded.fields)

            let pageSize = decoded.maxResults ?? maxResults
            let total = decoded.total ?? fields.count
            startAt += max(pageSize, decoded.fields.count)

            if decoded.fields.isEmpty || startAt >= total {
                break
            }
        }

        return fields.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchBiggestUnreleasedVersion() async throws -> JiraVersion? {
        let endpoint = apiURL("/rest/api/3/project/\(projectKey)/versions")
        let request = try buildRequest(urlString: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let versions = try JSONDecoder().decode([JiraVersion].self, from: data)

        let candidates = versions.filter { ($0.released ?? false) == false && ($0.archived ?? false) == false }

        return candidates
            .compactMap { version -> (JiraVersion, SemanticVersion)? in
                guard let semver = SemanticVersion.parse(from: version.name) else { return nil }
                return (version, semver)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    func createIssue(
        summary: String,
        description: [String: Any],
        fixVersionId: String?,
        defaultFields: [String: Any] = [:]
    ) async throws -> JiraIssueResponse {
        let endpoint = apiURL("/rest/api/3/issue")
        var fields = defaultFields

        if fields["issuetype"] == nil {
            fields["issuetype"] = ["name": "Bug"]
        }

        fields.merge([
            "project": ["key": projectKey],
            "summary": summary,
            "description": description
        ]) { _, appValue in appValue }

        if let id = fixVersionId {
            fields["fixVersions"] = [["id": id]]
        }

        let payload: [String: Any] = ["fields": fields]

        var request = try buildRequest(urlString: endpoint, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(JiraIssueResponse.self, from: data)
    }

    func updateIssueDescription(issueKey: String, description: [String: Any]) async throws {
        let endpoint = apiURL("/rest/api/3/issue/\(issueKey)")
        let payload: [String: Any] = [
            "fields": [
                "description": description
            ]
        ]

        var request = try buildRequest(urlString: endpoint, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func attachFile(issueKey: String, data: Data, fileName: String, contentType: String) async throws -> JiraAttachmentMetadata {
        let endpoint = apiURL("/rest/api/3/issue/\(issueKey)/attachments")
        var request = try buildRequest(urlString: endpoint, method: "POST")
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            fileName: fileName,
            data: data,
            contentType: contentType
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let attachments = try JSONDecoder().decode([JiraAttachmentMetadata].self, from: data)
        guard let first = attachments.first else {
            throw NSError(domain: "Jira", code: 2, userInfo: [NSLocalizedDescriptionKey: "Attachment upload succeeded but returned no metadata"])
        }
        return first
    }

    private func buildRequest(urlString: String, method: String) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Jira", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Jira URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let credentials = "\(email):\(apiToken)"
        let auth = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func apiURL(_ path: String) -> String {
        let base = workspaceURL.hasSuffix("/") ? String(workspaceURL.dropLast()) : workspaceURL
        return "\(base)\(path)"
    }

    private func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Jira", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }
    }

    private func multipartBody(boundary: String, fileName: String, data: Data, contentType: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    func adfDescription(from text: String) -> [String: Any] {
        [
            "type": "doc",
            "version": 1,
            "content": adfParagraphs(from: text)
        ]
    }

    func adfDescription(from text: String, attachments: [JiraAttachmentMetadata]) -> [String: Any] {
        adfDescription(from: text, attachments: attachments, includeRichMedia: true)
    }

    func adfDescriptionWithAttachmentLinks(from text: String, attachments: [JiraAttachmentMetadata]) -> [String: Any] {
        adfDescription(from: text, attachments: attachments, includeRichMedia: false)
    }

    private func adfDescription(from text: String, attachments: [JiraAttachmentMetadata], includeRichMedia: Bool) -> [String: Any] {
        var content = adfParagraphs(from: text)

        guard !attachments.isEmpty else {
            return [
                "type": "doc",
                "version": 1,
                "content": content
            ]
        }

        content.append([
            "type": "heading",
            "attrs": ["level": 2],
            "content": [[
                "type": "text",
                "text": "Media"
            ]]
        ])

        for attachment in attachments {
            if includeRichMedia, let mediaNode = adfMediaNode(for: attachment) {
                content.append(mediaNode)
            }

            if let url = attachment.content {
                content.append(linkParagraph(text: attachment.filename, url: url))
            } else {
                content.append(paragraph(text: attachment.filename))
            }
        }

        return [
            "type": "doc",
            "version": 1,
            "content": content
        ]
    }

    private func adfParagraphs(from text: String) -> [[String: Any]] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { paragraph(text: String($0)) }
    }

    private func paragraph(text: String) -> [String: Any] {
        if text.isEmpty {
            return [
                "type": "paragraph",
                "content": []
            ]
        }

        return [
            "type": "paragraph",
            "content": [[
                "type": "text",
                "text": text
            ]]
        ]
    }

    private func linkParagraph(text: String, url: String) -> [String: Any] {
        [
            "type": "paragraph",
            "content": [[
                "type": "text",
                "text": text,
                "marks": [[
                    "type": "link",
                    "attrs": ["href": url]
                ]]
            ]]
        ]
    }

    private func adfMediaNode(for attachment: JiraAttachmentMetadata) -> [String: Any]? {
        guard let url = attachment.content else { return nil }

        return [
            "type": "mediaSingle",
            "attrs": [
                "layout": "center"
            ],
            "content": [[
                "type": "media",
                "attrs": [
                    "type": "external",
                    "url": url,
                    "alt": attachment.filename
                ]
            ]]
        ]
    }
}
