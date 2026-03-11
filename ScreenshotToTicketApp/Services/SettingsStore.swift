import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var jiraEmail: String
    @Published var jiraApiToken: String
    @Published var openAIKey: String
    @Published var workspaceURL: String
    @Published var projectKey: String
    @Published var model: String

    private let defaults = UserDefaults.standard

    init() {
        jiraEmail = KeychainService.shared.read(.jiraEmail)
        jiraApiToken = KeychainService.shared.read(.jiraApiToken)
        openAIKey = KeychainService.shared.read(.openAIKey)

        workspaceURL = defaults.string(forKey: "workspaceURL") ?? "https://iagentur.jira.com"
        projectKey = defaults.string(forKey: "projectKey") ?? "TMNEWS"
        model = defaults.string(forKey: "openaiModel") ?? "gpt-5.4-codex"
    }

    func save() throws {
        projectKey = projectKey.uppercased()
        try KeychainService.shared.save(jiraEmail, for: .jiraEmail)
        try KeychainService.shared.save(jiraApiToken, for: .jiraApiToken)
        try KeychainService.shared.save(openAIKey, for: .openAIKey)

        defaults.set(workspaceURL, forKey: "workspaceURL")
        defaults.set(projectKey, forKey: "projectKey")
        defaults.set(model, forKey: "openaiModel")
    }

    var isConfigured: Bool {
        !jiraEmail.isEmpty && !jiraApiToken.isEmpty && !openAIKey.isEmpty
    }
}
