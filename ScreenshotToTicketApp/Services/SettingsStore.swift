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
    @Published var jiraProfiles: [JiraProfile]
    @Published var activeJiraProfileID: String
    @Published var model: String
    @Published var reasoningEffort: ReasoningEffort
    @Published var ticketPrompt: String

    private enum DefaultsKey {
        static let workspaceURL = "workspaceURL"
        static let legacyProjectKey = "projectKey"
        static let jiraProfiles = "jiraProfiles"
        static let activeJiraProfileID = "activeJiraProfileID"
        static let openAIModel = "openaiModel"
        static let reasoningEffort = "openaiReasoningEffort"
        static let ticketPrompt = "ticketPrompt"
    }

    private static let reservedDefaultFieldKeys: Set<String> = [
        "project",
        "summary",
        "description",
        "fixversions"
    ]

    private let defaults = UserDefaults.standard

    init() {
        jiraEmail = KeychainService.shared.read(.jiraEmail)
        jiraApiToken = KeychainService.shared.read(.jiraApiToken)
        openAIKey = KeychainService.shared.read(.openAIKey)

        workspaceURL = defaults.string(forKey: DefaultsKey.workspaceURL) ?? "https://iagentur.jira.com"
        model = defaults.string(forKey: DefaultsKey.openAIModel) ?? "gpt-5.5"
        reasoningEffort = defaults.string(forKey: DefaultsKey.reasoningEffort).flatMap(ReasoningEffort.init(rawValue:)) ?? .medium
        ticketPrompt = defaults.string(forKey: DefaultsKey.ticketPrompt).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? OpenAIClient.defaultTicketPrompt

        let legacyProjectKey = defaults.string(forKey: DefaultsKey.legacyProjectKey) ?? "TMNEWS"
        let storedProfiles = Self.loadProfiles(from: defaults)
        let loadedProfiles = Self.normalizedProfiles(
            storedProfiles.isEmpty
                ? [JiraProfile(name: legacyProjectKey.uppercased(), projectKey: legacyProjectKey)]
                : storedProfiles
        )
        let loadedActiveProfileID = Self.validActiveProfileID(
            defaults.string(forKey: DefaultsKey.activeJiraProfileID),
            profiles: loadedProfiles
        )
        jiraProfiles = loadedProfiles
        activeJiraProfileID = loadedActiveProfileID

        if storedProfiles.isEmpty, let encodedProfiles = try? JSONEncoder().encode(jiraProfiles) {
            defaults.set(encodedProfiles, forKey: DefaultsKey.jiraProfiles)
            defaults.set(activeJiraProfileID, forKey: DefaultsKey.activeJiraProfileID)
            defaults.set(activeJiraProfile?.projectKey ?? "", forKey: DefaultsKey.legacyProjectKey)
        }
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

        let normalizedProfiles = try Self.validatedProfiles(jiraProfiles)
        jiraProfiles = normalizedProfiles
        activeJiraProfileID = Self.validActiveProfileID(activeJiraProfileID, profiles: normalizedProfiles)
        ticketPrompt = trimmedPrompt

        try KeychainService.shared.save(jiraEmail, for: .jiraEmail)
        try KeychainService.shared.save(jiraApiToken, for: .jiraApiToken)
        try KeychainService.shared.save(openAIKey, for: .openAIKey)

        let encodedProfiles = try JSONEncoder().encode(jiraProfiles)
        defaults.set(workspaceURL, forKey: DefaultsKey.workspaceURL)
        defaults.set(activeJiraProfile?.projectKey ?? "", forKey: DefaultsKey.legacyProjectKey)
        defaults.set(encodedProfiles, forKey: DefaultsKey.jiraProfiles)
        defaults.set(activeJiraProfileID, forKey: DefaultsKey.activeJiraProfileID)
        defaults.set(model, forKey: DefaultsKey.openAIModel)
        defaults.set(reasoningEffort.rawValue, forKey: DefaultsKey.reasoningEffort)
        defaults.set(ticketPrompt, forKey: DefaultsKey.ticketPrompt)
    }

    var isConfigured: Bool {
        !jiraEmail.isEmpty
            && !jiraApiToken.isEmpty
            && !openAIKey.isEmpty
            && (activeJiraProfile?.projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    var activeJiraProfile: JiraProfile? {
        jiraProfiles.first { $0.id == activeJiraProfileID } ?? jiraProfiles.first
    }

    func updateActiveJiraProfile(_ update: (inout JiraProfile) -> Void) {
        guard let index = jiraProfiles.firstIndex(where: { $0.id == activeJiraProfileID }) else { return }
        update(&jiraProfiles[index])
    }

    func activateOrCreateProfile(from project: JiraProject) {
        let projectKey = project.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !projectKey.isEmpty else { return }

        if let index = jiraProfiles.firstIndex(where: { $0.projectKey.uppercased() == projectKey }) {
            activeJiraProfileID = jiraProfiles[index].id
            return
        }

        let profileName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = JiraProfile(
            name: profileName.isEmpty ? projectKey : profileName,
            projectKey: projectKey
        )
        jiraProfiles.append(profile)
        activeJiraProfileID = profile.id
    }

    func deleteActiveJiraProfile() {
        guard jiraProfiles.count > 1,
              let index = jiraProfiles.firstIndex(where: { $0.id == activeJiraProfileID }) else {
            return
        }

        jiraProfiles.remove(at: index)
        activeJiraProfileID = jiraProfiles[min(index, jiraProfiles.count - 1)].id
    }

    func defaultFields(for profile: JiraProfile) throws -> [String: Any] {
        try Self.parseDefaultFieldsJSON(profile.defaultFieldsJSON)
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

    private static func loadProfiles(from defaults: UserDefaults) -> [JiraProfile] {
        guard let data = defaults.data(forKey: DefaultsKey.jiraProfiles),
              let profiles = try? JSONDecoder().decode([JiraProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    private static func validatedProfiles(_ profiles: [JiraProfile]) throws -> [JiraProfile] {
        let normalized = normalizedProfiles(profiles)
        for profile in normalized {
            guard !profile.projectKey.isEmpty else {
                throw NSError(
                    domain: "SettingsStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Jira profile \"\(profile.name)\" needs a project key."]
                )
            }

            do {
                _ = try parseDefaultFieldsJSON(profile.defaultFieldsJSON)
            } catch {
                throw NSError(
                    domain: "SettingsStore",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Default fields for \"\(profile.name)\": \(error.localizedDescription)"]
                )
            }
        }
        return normalized
    }

    private static func normalizedProfiles(_ profiles: [JiraProfile]) -> [JiraProfile] {
        let sourceProfiles = profiles.isEmpty ? [JiraProfile(name: "TMNEWS", projectKey: "TMNEWS")] : profiles
        var seenIDs: Set<String> = []

        return sourceProfiles.map { profile in
            var normalized = profile
            let trimmedID = normalized.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty || seenIDs.contains(trimmedID) {
                normalized.id = UUID().uuidString
            } else {
                normalized.id = trimmedID
            }
            seenIDs.insert(normalized.id)

            normalized.projectKey = normalized.projectKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.name.isEmpty {
                normalized.name = normalized.projectKey.isEmpty ? "Jira Profile" : normalized.projectKey
            }

            normalized.defaultFieldsJSON = normalized.defaultFieldsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.defaultFieldsJSON.isEmpty {
                normalized.defaultFieldsJSON = "{}"
            }
            return normalized
        }
    }

    private static func validActiveProfileID(_ activeID: String?, profiles: [JiraProfile]) -> String {
        if let activeID, profiles.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return profiles.first?.id ?? UUID().uuidString
    }

    private static func parseDefaultFieldsJSON(_ json: String) throws -> [String: Any] {
        let trimmedJSON = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedJSON.isEmpty else { return [:] }

        let data = Data(trimmedJSON.utf8)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NSError(
                domain: "SettingsStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "must be valid JSON."]
            )
        }

        guard let fields = object as? [String: Any] else {
            throw NSError(
                domain: "SettingsStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "must be a JSON object."]
            )
        }

        if let reservedKey = fields.keys.first(where: { reservedDefaultFieldKeys.contains($0.lowercased()) }) {
            throw NSError(
                domain: "SettingsStore",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "\"\(reservedKey)\" is set by the app and cannot be used as a default field."]
            )
        }

        return fields
    }
}
