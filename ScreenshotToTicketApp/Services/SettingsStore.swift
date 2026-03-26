import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    enum ReasoningEffort: String, CaseIterable, Identifiable {
        case medium
        case high
        case xhigh

        var id: String { rawValue }

        var label: String {
            rawValue.capitalized
        }
    }

    @Published var jiraEmail: String
    @Published var jiraApiToken: String
    @Published var openAIKey: String
    @Published var workspaceURL: String
    @Published var projectKey: String
    @Published var model: String
    @Published var reasoningEffort: ReasoningEffort
    @Published var ticketPrompt: String

    private let defaults = UserDefaults.standard
    private let ticketPromptKey = "ticketPrompt"
    private let reasoningEffortKey = "openaiReasoningEffort"

    init() {
        jiraEmail = KeychainService.shared.read(.jiraEmail)
        jiraApiToken = KeychainService.shared.read(.jiraApiToken)
        openAIKey = KeychainService.shared.read(.openAIKey)

        workspaceURL = defaults.string(forKey: "workspaceURL") ?? "https://iagentur.jira.com"
        projectKey = defaults.string(forKey: "projectKey") ?? "TMNEWS"
        model = defaults.string(forKey: "openaiModel") ?? "gpt-5.5"
        reasoningEffort = defaults.string(forKey: reasoningEffortKey).flatMap(ReasoningEffort.init(rawValue:)) ?? .medium
        ticketPrompt = defaults.string(forKey: ticketPromptKey).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? OpenAIClient.defaultTicketPrompt
    }

    func save() throws {
        let trimmedPrompt = ticketPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw NSError(
                domain: "SettingsStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ticket prompt cannot be empty."]
            )
        }

        projectKey = projectKey.uppercased()
        ticketPrompt = trimmedPrompt
        try KeychainService.shared.save(jiraEmail, for: .jiraEmail)
        try KeychainService.shared.save(jiraApiToken, for: .jiraApiToken)
        try KeychainService.shared.save(openAIKey, for: .openAIKey)

        defaults.set(workspaceURL, forKey: "workspaceURL")
        defaults.set(projectKey, forKey: "projectKey")
        defaults.set(model, forKey: "openaiModel")
        defaults.set(reasoningEffort.rawValue, forKey: reasoningEffortKey)
        defaults.set(ticketPrompt, forKey: ticketPromptKey)
    }

    var isConfigured: Bool {
        !jiraEmail.isEmpty && !jiraApiToken.isEmpty && !openAIKey.isEmpty
    }

    var effectiveTicketPrompt: String {
        let trimmedPrompt = ticketPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? OpenAIClient.defaultTicketPrompt : trimmedPrompt
    }

    var isTicketPromptValid: Bool {
        !ticketPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isUsingDefaultTicketPrompt: Bool {
        effectiveTicketPrompt == OpenAIClient.defaultTicketPrompt
    }

    func resetTicketPromptToDefault() {
        ticketPrompt = OpenAIClient.defaultTicketPrompt
    }
}
