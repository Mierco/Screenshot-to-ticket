import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    enum JiraAuthMethod: String, CaseIterable, Identifiable {
        case apiToken
        case atlassianOAuth

        var id: String { rawValue }

        var label: String {
            switch self {
            case .apiToken:
                return "API Token"
            case .atlassianOAuth:
                return "Jira Login"
            }
        }
    }

    enum ReasoningEffort: String, CaseIterable, Identifiable {
        case medium
        case high
        case xhigh

        var id: String { rawValue }

        var label: String {
            rawValue.capitalized
        }
    }

    @Published var jiraAuthMethod: JiraAuthMethod
    @Published var jiraEmail: String
    @Published var jiraApiToken: String
    @Published private(set) var jiraOAuthAccessToken: String
    @Published private(set) var jiraOAuthRefreshToken: String
    @Published private(set) var jiraOAuthCloudID: String
    @Published private(set) var jiraOAuthSiteName: String
    @Published private(set) var jiraOAuthTokenExpiresAt: Date?
    @Published var openAIKey: String
    @Published var workspaceURL: String
    @Published var jiraProfiles: [JiraProfile]
    @Published var activeJiraProfileID: String
    @Published var model: String
    @Published var reasoningEffort: ReasoningEffort
    @Published var ticketPrompt: String

    private enum DefaultsKey {
        static let jiraAuthMethod = "jiraAuthMethod"
        static let jiraOAuthCloudID = "jiraOAuthCloudID"
        static let jiraOAuthSiteName = "jiraOAuthSiteName"
        static let jiraOAuthTokenExpiresAt = "jiraOAuthTokenExpiresAt"
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
        "description"
    ]

    private let defaults = UserDefaults.standard

    init() {
        jiraAuthMethod = defaults.string(forKey: DefaultsKey.jiraAuthMethod).flatMap(JiraAuthMethod.init(rawValue:)) ?? .apiToken
        jiraEmail = KeychainService.shared.read(.jiraEmail)
        jiraApiToken = KeychainService.shared.read(.jiraApiToken)
        jiraOAuthAccessToken = KeychainService.shared.read(.jiraOAuthAccessToken)
        jiraOAuthRefreshToken = KeychainService.shared.read(.jiraOAuthRefreshToken)
        jiraOAuthCloudID = defaults.string(forKey: DefaultsKey.jiraOAuthCloudID) ?? ""
        jiraOAuthSiteName = defaults.string(forKey: DefaultsKey.jiraOAuthSiteName) ?? ""
        jiraOAuthTokenExpiresAt = defaults.object(forKey: DefaultsKey.jiraOAuthTokenExpiresAt) as? Date
        openAIKey = KeychainService.shared.read(.openAIKey)

        let storedWorkspaceURL = defaults.string(forKey: DefaultsKey.workspaceURL)
        let legacyWorkspaceURL = storedWorkspaceURL ?? ""
        workspaceURL = legacyWorkspaceURL
        model = defaults.string(forKey: DefaultsKey.openAIModel) ?? "gpt-5.5"
        reasoningEffort = defaults.string(forKey: DefaultsKey.reasoningEffort).flatMap(ReasoningEffort.init(rawValue:)) ?? .medium
        ticketPrompt = defaults.string(forKey: DefaultsKey.ticketPrompt).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? OpenAIClient.defaultTicketPrompt

        let legacyProjectKey = defaults.string(forKey: DefaultsKey.legacyProjectKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasStoredProfilesData = defaults.data(forKey: DefaultsKey.jiraProfiles) != nil
        let loadedStoredProfiles = Self.loadProfiles(from: defaults)
        let storedProfiles = Self.removingGeneratedLegacyProfile(
            from: loadedStoredProfiles,
            legacyProjectKey: legacyProjectKey,
            hasStoredWorkspaceURL: storedWorkspaceURL != nil
        )
        let didRemoveGeneratedLegacyProfile = storedProfiles.count != loadedStoredProfiles.count
        let sourceProfiles = !hasStoredProfilesData && !legacyProjectKey.isEmpty
            ? [JiraProfile(name: legacyProjectKey.uppercased(), projectKey: legacyProjectKey)]
            : storedProfiles
        let loadedProfiles = Self.normalizedProfiles(
            sourceProfiles,
            legacyWorkspaceURL: legacyWorkspaceURL
        )
        let loadedActiveProfileID = Self.validActiveProfileID(
            defaults.string(forKey: DefaultsKey.activeJiraProfileID),
            profiles: loadedProfiles
        )
        jiraProfiles = loadedProfiles
        activeJiraProfileID = loadedActiveProfileID
        workspaceURL = activeJiraProfile?.workspaceURL.isEmpty == false ? activeJiraProfile?.workspaceURL ?? legacyWorkspaceURL : legacyWorkspaceURL

        if didRemoveGeneratedLegacyProfile || (!hasStoredProfilesData && !jiraProfiles.isEmpty),
           let encodedProfiles = try? JSONEncoder().encode(jiraProfiles) {
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

        var sourceProfiles = jiraProfiles
        if let index = sourceProfiles.firstIndex(where: { $0.id == activeJiraProfileID }) {
            sourceProfiles[index].workspaceURL = workspaceURL
        }

        let normalizedProfiles = try Self.validatedProfiles(sourceProfiles)
        jiraProfiles = normalizedProfiles
        activeJiraProfileID = Self.validActiveProfileID(activeJiraProfileID, profiles: normalizedProfiles)
        workspaceURL = activeJiraProfile?.workspaceURL ?? workspaceURL
        ticketPrompt = trimmedPrompt

        try KeychainService.shared.save(jiraEmail, for: .jiraEmail)
        try KeychainService.shared.save(jiraApiToken, for: .jiraApiToken)
        try KeychainService.shared.save(jiraOAuthAccessToken, for: .jiraOAuthAccessToken)
        try KeychainService.shared.save(jiraOAuthRefreshToken, for: .jiraOAuthRefreshToken)
        try KeychainService.shared.save(openAIKey, for: .openAIKey)

        let encodedProfiles = try JSONEncoder().encode(jiraProfiles)
        defaults.set(jiraAuthMethod.rawValue, forKey: DefaultsKey.jiraAuthMethod)
        defaults.set(jiraOAuthCloudID, forKey: DefaultsKey.jiraOAuthCloudID)
        defaults.set(jiraOAuthSiteName, forKey: DefaultsKey.jiraOAuthSiteName)
        defaults.set(jiraOAuthTokenExpiresAt, forKey: DefaultsKey.jiraOAuthTokenExpiresAt)
        defaults.set(workspaceURL, forKey: DefaultsKey.workspaceURL)
        defaults.set(activeJiraProfile?.projectKey ?? "", forKey: DefaultsKey.legacyProjectKey)
        defaults.set(encodedProfiles, forKey: DefaultsKey.jiraProfiles)
        defaults.set(activeJiraProfileID, forKey: DefaultsKey.activeJiraProfileID)
        defaults.set(model, forKey: DefaultsKey.openAIModel)
        defaults.set(reasoningEffort.rawValue, forKey: DefaultsKey.reasoningEffort)
        defaults.set(ticketPrompt, forKey: DefaultsKey.ticketPrompt)
    }

    var isConfigured: Bool {
        hasJiraAuthentication
            && hasOpenAIConfiguration
            && (activeJiraProfile?.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            && (activeJiraProfile?.projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    var isSelectedAIProviderConfigured: Bool {
        hasOpenAIConfiguration
    }

    var hasOpenAIConfiguration: Bool {
        !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedAIModelName: String {
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelID.isEmpty ? "OpenAI" : modelID
    }

    var hasJiraAuthentication: Bool {
        switch jiraAuthMethod {
        case .apiToken:
            return !jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .atlassianOAuth:
            return !jiraOAuthAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraOAuthCloudID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var jiraConnectionSummary: String {
        switch jiraAuthMethod {
        case .apiToken:
            return hasJiraAuthentication ? "Workspace, email, and token set" : "Workspace URL, email, and API token required"
        case .atlassianOAuth:
            if hasJiraAuthentication {
                return jiraOAuthSiteName.isEmpty ? "Jira Cloud connected" : "Connected to \(jiraOAuthSiteName)"
            }
            return AtlassianOAuthConfiguration.current.isConfigured
                ? "Connect with Atlassian to authorize Jira Cloud"
                : "Atlassian OAuth is not configured for this build"
        }
    }

    func hasJiraConnection(workspaceURL: String? = nil) -> Bool {
        let candidateWorkspaceURL = (workspaceURL ?? self.workspaceURL).trimmingCharacters(in: .whitespacesAndNewlines)
        return !candidateWorkspaceURL.isEmpty && hasJiraAuthentication
    }

    func jiraClient(workspaceURL: String, projectKey: String) async throws -> JiraClient {
        switch jiraAuthMethod {
        case .apiToken:
            return JiraClient(
                workspaceURL: workspaceURL,
                email: jiraEmail,
                apiToken: jiraApiToken,
                projectKey: projectKey
            )
        case .atlassianOAuth:
            try await refreshJiraOAuthTokenIfNeeded()
            return JiraClient(
                workspaceURL: workspaceURL,
                auth: .bearer(accessToken: jiraOAuthAccessToken, cloudID: jiraOAuthCloudID),
                projectKey: projectKey
            )
        }
    }

    func connectAtlassianOAuth() async throws {
        let connection = try await AtlassianOAuthService().authorize(preferredWorkspaceURL: workspaceURL)
        jiraAuthMethod = .atlassianOAuth
        jiraOAuthAccessToken = connection.tokens.accessToken
        jiraOAuthRefreshToken = connection.tokens.refreshToken
        jiraOAuthTokenExpiresAt = connection.tokens.expiresAt
        jiraOAuthCloudID = connection.cloudID
        jiraOAuthSiteName = connection.siteName
        workspaceURL = connection.workspaceURL
        if let activeProfile = activeJiraProfile {
            updateActiveJiraProfile { profile in
                if profile.id == activeProfile.id {
                    profile.workspaceURL = connection.workspaceURL
                }
            }
        }
        try save()
    }

    func disconnectAtlassianOAuth() {
        jiraOAuthAccessToken = ""
        jiraOAuthRefreshToken = ""
        jiraOAuthCloudID = ""
        jiraOAuthSiteName = ""
        jiraOAuthTokenExpiresAt = nil
        try? KeychainService.shared.delete(.jiraOAuthAccessToken)
        try? KeychainService.shared.delete(.jiraOAuthRefreshToken)
        defaults.removeObject(forKey: DefaultsKey.jiraOAuthCloudID)
        defaults.removeObject(forKey: DefaultsKey.jiraOAuthSiteName)
        defaults.removeObject(forKey: DefaultsKey.jiraOAuthTokenExpiresAt)
    }

    func refreshJiraOAuthTokenIfNeeded(force: Bool = false) async throws {
        guard jiraAuthMethod == .atlassianOAuth else { return }
        let refreshToken = jiraOAuthRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else { return }

        let refreshThreshold = Date().addingTimeInterval(120)
        if !force,
           let expiresAt = jiraOAuthTokenExpiresAt,
           expiresAt > refreshThreshold,
           !jiraOAuthAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        let tokens = try await AtlassianOAuthService().refresh(refreshToken: refreshToken)
        jiraOAuthAccessToken = tokens.accessToken
        if !tokens.refreshToken.isEmpty {
            jiraOAuthRefreshToken = tokens.refreshToken
        }
        jiraOAuthTokenExpiresAt = tokens.expiresAt
        try KeychainService.shared.save(jiraOAuthAccessToken, for: .jiraOAuthAccessToken)
        try KeychainService.shared.save(jiraOAuthRefreshToken, for: .jiraOAuthRefreshToken)
        defaults.set(jiraOAuthTokenExpiresAt, forKey: DefaultsKey.jiraOAuthTokenExpiresAt)
    }

    var activeJiraProfile: JiraProfile? {
        jiraProfiles.first { $0.id == activeJiraProfileID } ?? jiraProfiles.first
    }

    func activateProfile(id: String) {
        guard jiraProfiles.contains(where: { $0.id == id }) else { return }
        activeJiraProfileID = id
        workspaceURL = activeJiraProfile?.workspaceURL ?? workspaceURL
        persistActiveProfileSelection()
    }

    func updateActiveJiraProfile(_ update: (inout JiraProfile) -> Void) {
        guard let index = jiraProfiles.firstIndex(where: { $0.id == activeJiraProfileID }) else { return }
        update(&jiraProfiles[index])
    }

    @discardableResult
    func createProfile(name: String, workspaceURL: String? = nil, projectKey: String, defaultFieldsJSON: String = "{}") throws -> JiraProfile {
        let workspaceURL = (workspaceURL ?? self.workspaceURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let projectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !workspaceURL.isEmpty else {
            throw NSError(
                domain: "SettingsStore",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Jira profile needs a workspace URL."]
            )
        }
        guard !projectKey.isEmpty else {
            throw NSError(
                domain: "SettingsStore",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Jira profile needs a project key."]
            )
        }

        if let index = jiraProfiles.firstIndex(where: {
            $0.projectKey.uppercased() == projectKey && Self.normalizedWorkspaceURL($0.workspaceURL) == Self.normalizedWorkspaceURL(workspaceURL)
        }) {
            activeJiraProfileID = jiraProfiles[index].id
            self.workspaceURL = jiraProfiles[index].workspaceURL
            persistActiveProfileSelection()
            return jiraProfiles[index]
        }

        let originalProfiles = jiraProfiles
        let originalActiveProfileID = activeJiraProfileID
        let originalWorkspaceURL = self.workspaceURL
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = JiraProfile(
            name: profileName.isEmpty ? projectKey : profileName,
            workspaceURL: workspaceURL,
            projectKey: projectKey,
            defaultFieldsJSON: defaultFieldsJSON
        )
        jiraProfiles.append(profile)
        activeJiraProfileID = profile.id
        self.workspaceURL = profile.workspaceURL
        do {
            try persistProfiles()
        } catch {
            jiraProfiles = originalProfiles
            activeJiraProfileID = originalActiveProfileID
            self.workspaceURL = originalWorkspaceURL
            throw error
        }
        return activeJiraProfile ?? profile
    }

    @discardableResult
    func createProfile(from project: JiraProject, name: String? = nil) throws -> JiraProfile {
        try createProfile(
            name: name ?? project.name,
            workspaceURL: workspaceURL,
            projectKey: project.key
        )
    }

    @discardableResult
    func duplicateProfile(id: String) throws -> JiraProfile {
        guard let sourceProfile = jiraProfiles.first(where: { $0.id == id }) else {
            throw NSError(
                domain: "SettingsStore",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Jira profile no longer exists."]
            )
        }

        let originalProfiles = jiraProfiles
        let originalActiveProfileID = activeJiraProfileID
        let profile = JiraProfile(
            name: duplicateProfileName(for: sourceProfile.name),
            workspaceURL: sourceProfile.workspaceURL,
            projectKey: sourceProfile.projectKey,
            defaultFieldsJSON: sourceProfile.defaultFieldsJSON
        )
        jiraProfiles.append(profile)

        do {
            try persistProfiles()
        } catch {
            jiraProfiles = originalProfiles
            activeJiraProfileID = originalActiveProfileID
            throw error
        }

        return jiraProfiles.first { $0.id == profile.id } ?? profile
    }

    func updateProfile(_ profile: JiraProfile) throws {
        guard let index = jiraProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let originalProfiles = jiraProfiles
        let originalActiveProfileID = activeJiraProfileID
        let originalWorkspaceURL = workspaceURL
        jiraProfiles[index] = profile
        do {
            try persistProfiles()
            if profile.id == activeJiraProfileID {
                workspaceURL = activeJiraProfile?.workspaceURL ?? workspaceURL
            }
        } catch {
            jiraProfiles = originalProfiles
            activeJiraProfileID = originalActiveProfileID
            workspaceURL = originalWorkspaceURL
            throw error
        }
    }

    func deleteProfile(id: String) throws {
        guard let index = jiraProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let originalProfiles = jiraProfiles
        let originalActiveProfileID = activeJiraProfileID
        jiraProfiles.remove(at: index)
        if jiraProfiles.isEmpty {
            activeJiraProfileID = ""
        } else if originalActiveProfileID == id || !jiraProfiles.contains(where: { $0.id == activeJiraProfileID }) {
            activeJiraProfileID = jiraProfiles[min(index, jiraProfiles.count - 1)].id
        }
        do {
            try persistProfiles()
        } catch {
            jiraProfiles = originalProfiles
            activeJiraProfileID = originalActiveProfileID
            throw error
        }
    }

    func deleteActiveJiraProfile() {
        try? deleteProfile(id: activeJiraProfileID)
    }

    func defaultFields(for profile: JiraProfile) throws -> [String: Any] {
        try Self.parseDefaultFieldsJSON(profile.defaultFieldsJSON)
    }

    func validateDefaultFieldsJSON(_ json: String) throws {
        _ = try Self.parseDefaultFieldsJSON(json)
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
            guard !profile.workspaceURL.isEmpty else {
                throw NSError(
                    domain: "SettingsStore",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Jira profile \"\(profile.name)\" needs a workspace URL."]
                )
            }

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

    private static func removingGeneratedLegacyProfile(
        from profiles: [JiraProfile],
        legacyProjectKey: String,
        hasStoredWorkspaceURL: Bool
    ) -> [JiraProfile] {
        guard !hasStoredWorkspaceURL,
              profiles.count == 1,
              !legacyProjectKey.isEmpty,
              let profile = profiles.first else {
            return profiles
        }

        let normalizedLegacyProjectKey = legacyProjectKey.uppercased()
        let normalizedDefaultFieldsJSON = profile.defaultFieldsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.projectKey.uppercased() == normalizedLegacyProjectKey,
              profile.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedLegacyProjectKey,
              normalizedDefaultFieldsJSON.isEmpty || normalizedDefaultFieldsJSON == "{}" else {
            return profiles
        }

        return []
    }

    private static func normalizedProfiles(_ profiles: [JiraProfile], legacyWorkspaceURL: String = "") -> [JiraProfile] {
        var seenIDs: Set<String> = []
        let fallbackWorkspaceURL = legacyWorkspaceURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return profiles.map { profile in
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
            normalized.workspaceURL = normalized.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.workspaceURL.isEmpty {
                normalized.workspaceURL = fallbackWorkspaceURL
            }
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
        return profiles.first?.id ?? ""
    }

    private func persistProfiles() throws {
        let normalizedProfiles = try Self.validatedProfiles(jiraProfiles)
        jiraProfiles = normalizedProfiles
        activeJiraProfileID = Self.validActiveProfileID(activeJiraProfileID, profiles: normalizedProfiles)
        workspaceURL = activeJiraProfile?.workspaceURL ?? workspaceURL

        let encodedProfiles = try JSONEncoder().encode(jiraProfiles)
        defaults.set(encodedProfiles, forKey: DefaultsKey.jiraProfiles)
        defaults.set(workspaceURL, forKey: DefaultsKey.workspaceURL)
        persistActiveProfileSelection()
    }

    private static func normalizedWorkspaceURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private func persistActiveProfileSelection() {
        defaults.set(activeJiraProfileID, forKey: DefaultsKey.activeJiraProfileID)
        defaults.set(activeJiraProfile?.projectKey ?? "", forKey: DefaultsKey.legacyProjectKey)
    }

    private func duplicateProfileName(for name: String) -> String {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Jira Profile"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingNames = Set(jiraProfiles.map { $0.name })
        let firstCandidate = "\(baseName) Copy"
        guard existingNames.contains(firstCandidate) else {
            return firstCandidate
        }

        var suffix = 2
        while existingNames.contains("\(firstCandidate) \(suffix)") {
            suffix += 1
        }
        return "\(firstCandidate) \(suffix)"
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
