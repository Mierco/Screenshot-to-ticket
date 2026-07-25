import AuthenticationServices
import Foundation
import UIKit

struct JiraClient {
    enum Auth {
        case basic(email: String, apiToken: String)
        case bearer(accessToken: String, cloudID: String)
    }

    let workspaceURL: String
    let auth: Auth
    let projectKey: String

    init(workspaceURL: String, email: String, apiToken: String, projectKey: String) {
        self.workspaceURL = workspaceURL
        self.auth = .basic(email: email, apiToken: apiToken)
        self.projectKey = projectKey
    }

    init(workspaceURL: String, auth: Auth, projectKey: String) {
        self.workspaceURL = workspaceURL
        self.auth = auth
        self.projectKey = projectKey
    }

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
        let versions = try await fetchProjectVersions()
        let candidates = versions.filter { ($0.released ?? false) == false && ($0.archived ?? false) == false }

        return candidates
            .compactMap { version -> (JiraVersion, SemanticVersion)? in
                guard let semver = SemanticVersion.parse(from: version.name) else { return nil }
                return (version, semver)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    func fetchProjectVersions() async throws -> [JiraVersion] {
        let endpoint = apiURL("/rest/api/3/project/\(projectKey)/versions")
        let request = try buildRequest(urlString: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([JiraVersion].self, from: data)
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

        if let id = fixVersionId, fields["fixVersions"] == nil {
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

        switch auth {
        case let .basic(email, apiToken):
            let credentials = "\(email):\(apiToken)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case let .bearer(accessToken, _):
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func apiURL(_ path: String) -> String {
        if case let .bearer(_, cloudID) = auth {
            return "https://api.atlassian.com/ex/jira/\(pathComponent(cloudID))\(path)"
        }

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

struct AtlassianOAuthConfiguration {
    let clientID: String
    let redirectURL: URL?
    let tokenBrokerURL: URL?

    static var current: AtlassianOAuthConfiguration {
        let bundle = Bundle.main
        return AtlassianOAuthConfiguration(
            clientID: bundle.object(forInfoDictionaryKey: "AtlassianOAuthClientID") as? String ?? "",
            redirectURL: (bundle.object(forInfoDictionaryKey: "AtlassianOAuthRedirectURL") as? String).flatMap(URL.init(string:)),
            tokenBrokerURL: (bundle.object(forInfoDictionaryKey: "AtlassianOAuthTokenBrokerURL") as? String).flatMap(URL.init(string:))
        )
    }

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && redirectURL != nil
            && tokenBrokerURL != nil
    }
}

struct AtlassianOAuthTokens {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct AtlassianOAuthConnection {
    let tokens: AtlassianOAuthTokens
    let cloudID: String
    let workspaceURL: String
    let siteName: String
}

final class AtlassianOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: AtlassianOAuthConfiguration
    private var currentSession: ASWebAuthenticationSession?
    private let scopes = [
        "read:jira-user",
        "read:jira-work",
        "write:jira-work",
        "offline_access"
    ]

    init(configuration: AtlassianOAuthConfiguration = .current) {
        self.configuration = configuration
    }

    func authorize(preferredWorkspaceURL: String) async throws -> AtlassianOAuthConnection {
        guard configuration.isConfigured,
              let redirectURL = configuration.redirectURL else {
            throw NSError(
                domain: "AtlassianOAuth",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Atlassian OAuth is not configured for this build."]
            )
        }

        let state = UUID().uuidString
        let code = try await requestAuthorizationCode(state: state, redirectURL: redirectURL)
        let tokens = try await exchangeAuthorizationCode(code, redirectURL: redirectURL)
        let resources = try await fetchAccessibleResources(accessToken: tokens.accessToken)

        guard let resource = preferredResource(from: resources, preferredWorkspaceURL: preferredWorkspaceURL) else {
            throw NSError(
                domain: "AtlassianOAuth",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No accessible Jira Cloud site was returned for this account."]
            )
        }

        return AtlassianOAuthConnection(
            tokens: tokens,
            cloudID: resource.id,
            workspaceURL: resource.url,
            siteName: resource.name
        )
    }

    func refresh(refreshToken: String) async throws -> AtlassianOAuthTokens {
        try await requestTokens(payload: [
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "refresh_token": refreshToken
        ])
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func requestAuthorizationCode(state: String, redirectURL: URL) async throws -> String {
        guard var components = URLComponents(string: "https://auth.atlassian.com/authorize") else {
            throw NSError(domain: "AtlassianOAuth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid Atlassian authorization URL."])
        }

        components.queryItems = [
            URLQueryItem(name: "audience", value: "api.atlassian.com"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authorizationURL = components.url else {
            throw NSError(domain: "AtlassianOAuth", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not build Atlassian authorization URL."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: redirectURL.scheme
            ) { callbackURL, error in
                self.currentSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    continuation.resume(throwing: NSError(domain: "AtlassianOAuth", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing Atlassian callback URL."]))
                    return
                }

                let returnedState = components.queryItems?.first { $0.name == "state" }?.value
                guard returnedState == state else {
                    continuation.resume(throwing: NSError(domain: "AtlassianOAuth", code: 6, userInfo: [NSLocalizedDescriptionKey: "Atlassian OAuth state did not match."]))
                    return
                }

                if let message = components.queryItems?.first(where: { $0.name == "error_description" })?.value
                    ?? components.queryItems?.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: NSError(domain: "AtlassianOAuth", code: 7, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }

                guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      !code.isEmpty else {
                    continuation.resume(throwing: NSError(domain: "AtlassianOAuth", code: 8, userInfo: [NSLocalizedDescriptionKey: "Atlassian callback did not include an authorization code."]))
                    return
                }

                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            session.start()
        }
    }

    private func exchangeAuthorizationCode(_ code: String, redirectURL: URL) async throws -> AtlassianOAuthTokens {
        try await requestTokens(payload: [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": redirectURL.absoluteString
        ])
    }

    private func requestTokens(payload: [String: String]) async throws -> AtlassianOAuthTokens {
        guard let tokenBrokerURL = configuration.tokenBrokerURL else {
            throw NSError(domain: "AtlassianOAuth", code: 9, userInfo: [NSLocalizedDescriptionKey: "Atlassian OAuth token broker URL is missing."])
        }

        var request = URLRequest(url: tokenBrokerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown OAuth token broker error"
            throw NSError(domain: "AtlassianOAuth", code: 10, userInfo: [NSLocalizedDescriptionKey: text])
        }

        let decoded = try JSONDecoder().decode(TokenBrokerResponse.self, from: data)
        guard !decoded.accessToken.isEmpty else {
            throw NSError(domain: "AtlassianOAuth", code: 11, userInfo: [NSLocalizedDescriptionKey: "Token broker returned no access token."])
        }

        return AtlassianOAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
    }

    private func fetchAccessibleResources(accessToken: String) async throws -> [AccessibleResource] {
        guard let url = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown Atlassian resource error"
            throw NSError(domain: "AtlassianOAuth", code: 12, userInfo: [NSLocalizedDescriptionKey: text])
        }

        return try JSONDecoder().decode([AccessibleResource].self, from: data)
    }

    private func preferredResource(from resources: [AccessibleResource], preferredWorkspaceURL: String) -> AccessibleResource? {
        let jiraResources = resources.filter { resource in
            resource.scopes.contains { $0.contains("jira") }
        }

        let normalizedPreferredURL = normalizedURL(preferredWorkspaceURL)
        if !normalizedPreferredURL.isEmpty,
           let matchingResource = jiraResources.first(where: { normalizedURL($0.url) == normalizedPreferredURL }) {
            return matchingResource
        }

        return jiraResources.first ?? resources.first
    }

    private func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

private struct TokenBrokerResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct AccessibleResource: Decodable {
    let id: String
    let url: String
    let name: String
    let scopes: [String]
}
