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

    func createIssue(summary: String, description: String, fixVersionId: String?) async throws -> JiraIssueResponse {
        let endpoint = apiURL("/rest/api/3/issue")
        var fields: [String: Any] = [
            "project": ["key": projectKey],
            "issuetype": ["name": "Bug"],
            "summary": summary,
            "description": adfDescription(from: description)
        ]

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

    func attachFile(issueKey: String, data: Data, fileName: String, contentType: String) async throws {
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

    private func adfDescription(from text: String) -> [String: Any] {
        let paragraphs: [[String: Any]] = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                [
                    "type": "paragraph",
                    "content": [[
                        "type": "text",
                        "text": String(line)
                    ]]
                ]
            }

        return [
            "type": "doc",
            "version": 1,
            "content": paragraphs
        ]
    }
}
