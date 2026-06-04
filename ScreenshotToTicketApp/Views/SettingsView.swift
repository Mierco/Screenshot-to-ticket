import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var saveMessage = ""
    @State private var authMessage = ""
    @State private var isTestingAuth = false
    @State private var isAddingProfile = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(settings.isConfigured ? "Ready to submit" : "Setup incomplete", systemImage: settings.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(settings.isConfigured ? settingsAccent : .orange)

                            Spacer()

                            Text(settings.reasoningEffort.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        }

                        VStack(spacing: 0) {
                            SettingsReadinessRow(
                                title: "Jira connection",
                                value: jiraConnectionSummary,
                                isReady: hasJiraConnection
                            )

                            Divider()
                                .padding(.leading, 32)

                            SettingsReadinessRow(
                                title: "Jira profile",
                                value: jiraProfileSummary,
                                isReady: settings.activeJiraProfile != nil
                            )

                            Divider()
                                .padding(.leading, 32)

                            SettingsReadinessRow(
                                title: "OpenAI",
                                value: openAISummary,
                                isReady: !settings.openAIKey.isEmpty && !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Jira Connection") {
                    TextField("Workspace URL", text: $settings.workspaceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Atlassian Email", text: $settings.jiraEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Jira API Token", text: $settings.jiraApiToken)

                    Button {
                        Task { await testJiraAccess() }
                    } label: {
                        if isTestingAuth {
                            ProgressView()
                        } else {
                            Text("Test Jira Access")
                        }
                    }
                    .disabled(isTestingAuth || !hasJiraConnection)

                    if !authMessage.isEmpty {
                        SettingsMessageView(message: authMessage)
                    }
                }

                Section {
                    if settings.jiraProfiles.isEmpty {
                        Text("No Jira profiles configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Active Profile", selection: activeJiraProfileSelection) {
                            ForEach(settings.jiraProfiles) { profile in
                                Text("\(profile.name) (\(profile.projectKey))")
                                    .tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)

                        ForEach(settings.jiraProfiles) { profile in
                            NavigationLink {
                                JiraProfileDetailView(profileID: profile.id)
                                    .environmentObject(settings)
                            } label: {
                                JiraProfileListRow(
                                    profile: profile,
                                    isActive: profile.id == settings.activeJiraProfileID
                                )
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Jira Profile")
                        Spacer()
                        Button {
                            isAddingProfile = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!hasJiraConnection)
                        .accessibilityLabel("Add Profile")
                    }
                } footer: {
                    if !hasJiraConnection {
                        Text("Add your Jira connection details before creating profiles.")
                    } else if settings.jiraProfiles.isEmpty {
                        Text("Create a Jira profile before submitting tickets.")
                    } else {
                        Text("Choose the active profile here. Tap any profile below to edit it.")
                    }
                }

                Section("OpenAI") {
                    SecureField("OpenAI API Key", text: $settings.openAIKey)
                    TextField("Model ID", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Thinking", selection: $settings.reasoningEffort) {
                        ForEach(SettingsStore.ReasoningEffort.allCases) { effort in
                            Text(effort.label).tag(effort)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextEditor(text: $settings.ticketPrompt)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !settings.isTicketPromptValid {
                        Text("Ticket prompt cannot be empty.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Reset to Default Prompt") {
                        settings.resetTicketPromptToDefault()
                        saveMessage = ""
                    }
                    .disabled(settings.isUsingDefaultTicketPrompt)
                } header: {
                    Text("Ticket Prompt")
                } footer: {
                    Text("This base prompt is combined with the hints/instructions from the main screen.")
                }

                Section {
                    Button("Save Connection and OpenAI Settings") {
                        do {
                            try settings.save()
                            saveMessage = "Saved."
                        } catch {
                            saveMessage = "Save failed: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if !saveMessage.isEmpty {
                        SettingsMessageView(message: saveMessage)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isAddingProfile) {
                AddJiraProfileView()
                    .environmentObject(settings)
            }
        }
    }

    private var settingsAccent: Color {
        Color(red: 0.57, green: 0.78, blue: 0.00)
    }

    private var hasJiraConnection: Bool {
        !settings.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeJiraProfileSelection: Binding<String> {
        Binding(
            get: { settings.activeJiraProfileID },
            set: { settings.activateProfile(id: $0) }
        )
    }

    private var jiraConnectionSummary: String {
        hasJiraConnection ? "Workspace, email, and token set" : "Workspace URL, email, and API token required"
    }

    private var jiraProfileSummary: String {
        guard let profile = settings.activeJiraProfile else {
            return "Create or select a Jira profile"
        }
        return "\(profile.name) - \(profile.projectKey)"
    }

    private var openAISummary: String {
        if settings.openAIKey.isEmpty {
            return "API key required"
        }
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "Model ID required" : model
    }

    private func testJiraAccess() async {
        isTestingAuth = true
        authMessage = ""
        defer { isTestingAuth = false }

        do {
            let activeProjectKey = settings.activeJiraProfile?.projectKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: activeProjectKey
            )

            let me = try await jira.fetchCurrentUser()
            let display = me.emailAddress ?? me.displayName

            if activeProjectKey.isEmpty {
                authMessage = "Auth OK as \(display). Select a Jira profile to test project access."
                return
            }

            try await jira.validateProjectAccess(projectKey: activeProjectKey)
            authMessage = "Auth OK as \(display). Project \(activeProjectKey) is accessible."
        } catch {
            authMessage = "Access test failed: \(error.localizedDescription)"
        }
    }
}

private struct SettingsReadinessRow: View {
    let title: String
    let value: String
    let isReady: Bool

    private var accent: Color {
        Color(red: 0.57, green: 0.78, blue: 0.00)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? accent : Color.secondary.opacity(0.65))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(minHeight: 44)
    }
}

private struct JiraProfileListRow: View {
    let profile: JiraProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .foregroundStyle(.primary)
                Text(profile.projectKey)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Active")
            }
        }
    }
}

private struct AddJiraProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var projects: [JiraProject] = []
    @State private var selectedProjectID = ""
    @State private var profileName = ""
    @State private var defaultFieldsJSON = "{}"
    @State private var searchText = ""
    @State private var message = ""
    @State private var isLoadingProjects = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoadingProjects {
                        HStack {
                            ProgressView()
                            Text("Loading Jira projects...")
                                .foregroundStyle(.secondary)
                        }
                    } else if projects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No projects loaded.")
                                .foregroundStyle(.secondary)
                            Button("Load Jira Projects") {
                                Task { await loadProjects() }
                            }
                        }
                    } else {
                        projectList
                    }
                } header: {
                    Text("Project")
                } footer: {
                    Text("Search and choose the Jira project this profile should use.")
                }

                if let project = selectedProject {
                    Section("Profile") {
                        TextField("Profile Name", text: $profileName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        LabeledContent("Project Key", value: project.key)

                        if selectedProjectExistingProfile != nil {
                            Text("A profile for this project already exists. You can activate it instead of creating a duplicate.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if selectedProjectExistingProfile == nil {
                        Section("Default Fields") {
                            JiraDefaultFieldsEditor(projectKey: project.key, defaultFieldsJSON: $defaultFieldsJSON)
                        }
                    }

                    Section {
                        Button {
                            createOrActivateProfile()
                        } label: {
                            Label(
                                selectedProjectExistingProfile == nil ? "Create Profile" : "Activate Existing Profile",
                                systemImage: selectedProjectExistingProfile == nil ? "plus.circle.fill" : "checkmark.circle.fill"
                            )
                        }
                        .disabled(!canFinish)
                    }
                }

                if !message.isEmpty {
                    Section {
                        SettingsMessageView(message: message)
                    }
                }
            }
            .navigationTitle("Add Profile")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadProjects() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoadingProjects)
                    .accessibilityLabel("Refresh Jira Projects")
                }
            }
            .task {
                guard projects.isEmpty else { return }
                await loadProjects()
            }
        }
    }

    private var projectList: some View {
        ForEach(filteredProjectRows) { row in
            projectRow(row.project)
        }
    }

    private func projectRow(_ project: JiraProject) -> some View {
        Button {
            select(project)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Text(project.key)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if existingProfile(for: project) != nil {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectedProjectID == project.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var filteredProjectRows: [ProjectRow] {
        filteredProjects.map { ProjectRow(project: $0) }
    }

    private var filteredProjects: [JiraProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.lowercased().contains(query)
                || project.key.lowercased().contains(query)
        }
    }

    private var selectedProject: JiraProject? {
        projects.first { $0.id == selectedProjectID }
    }

    private var selectedProjectExistingProfile: JiraProfile? {
        guard let selectedProject else { return nil }
        return existingProfile(for: selectedProject)
    }

    private var canFinish: Bool {
        guard selectedProject != nil else { return false }
        if selectedProjectExistingProfile != nil { return true }
        return !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && defaultFieldsValidationMessage == nil
    }

    private var defaultFieldsValidationMessage: String? {
        do {
            try settings.validateDefaultFieldsJSON(defaultFieldsJSON)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func existingProfile(for project: JiraProject) -> JiraProfile? {
        settings.jiraProfiles.first {
            $0.projectKey.uppercased() == project.key.uppercased()
        }
    }

    private func select(_ project: JiraProject) {
        selectedProjectID = project.id
        if let existingProfile = existingProfile(for: project) {
            profileName = existingProfile.name
        } else {
            profileName = project.name
            defaultFieldsJSON = "{}"
        }
        message = ""
    }

    private func loadProjects() async {
        guard hasJiraConnection else {
            message = "Fill in Jira Workspace URL, email, and API token first."
            return
        }

        isLoadingProjects = true
        message = ""
        defer { isLoadingProjects = false }

        do {
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: settings.activeJiraProfile?.projectKey ?? ""
            )
            projects = try await jira.fetchAccessibleProjects()
            selectedProjectID = ""
            profileName = ""
            defaultFieldsJSON = "{}"
            message = projects.isEmpty
                ? "No accessible projects found for this account."
                : "Loaded \(projects.count) projects."
        } catch {
            message = "Failed to load projects: \(error.localizedDescription)"
        }
    }

    private func createOrActivateProfile() {
        guard let project = selectedProject else { return }

        do {
            if let existingProfile = selectedProjectExistingProfile {
                settings.activateProfile(id: existingProfile.id)
            } else {
                _ = try settings.createProfile(
                    name: profileName,
                    projectKey: project.key,
                    defaultFieldsJSON: defaultFieldsJSON
                )
            }
            dismiss()
        } catch {
            message = "Failed to create profile: \(error.localizedDescription)"
        }
    }

    private var hasJiraConnection: Bool {
        !settings.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct ProjectRow: Identifiable {
        let project: JiraProject

        var id: String { project.id }
    }
}

private struct JiraProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    let profileID: String

    @State private var profileName = ""
    @State private var projectKey = ""
    @State private var defaultFieldsJSON = "{}"
    @State private var message = ""
    @State private var isSelectingProject = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Form {
            if let profile {
                Section("Profile") {
                    TextField("Profile Name", text: $profileName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Project") {
                    LabeledContent("Project Key", value: projectKey)

                    Button {
                        isSelectingProject = true
                    } label: {
                        Label("Change Project", systemImage: "folder.badge.gearshape")
                    }
                }

                Section("Default Fields") {
                    JiraDefaultFieldsEditor(projectKey: projectKey, defaultFieldsJSON: $defaultFieldsJSON)
                }

                Section {
                    Button("Make Active Profile") {
                        settings.activateProfile(id: profile.id)
                        message = "Activated \(profileName)."
                    }
                    .disabled(settings.activeJiraProfileID == profile.id)

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .disabled(!canSave)

                    Button("Delete Profile", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }

                    Button {
                        duplicateProfile()
                    } label: {
                        Label("Duplicate Profile", systemImage: "plus.square.on.square")
                    }
                }

                if !message.isEmpty {
                    Section {
                        SettingsMessageView(message: message)
                    }
                }
            } else {
                Section {
                    Text("This Jira profile no longer exists.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProfile()
                }
                .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "Delete Jira Profile?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                deleteProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile from this device.")
        }
        .onAppear(perform: loadProfileDraft)
        .onChange(of: profileID) { _ in
            loadProfileDraft()
        }
        .fullScreenCover(isPresented: $isSelectingProject) {
            JiraProjectPickerView(
                title: "Change Project",
                currentProjectKey: projectKey,
                showsExistingProfileBadges: true
            ) { project in
                projectKey = project.key
                message = ""
            }
            .environmentObject(settings)
        }
    }

    private var profile: JiraProfile? {
        settings.jiraProfiles.first { $0.id == profileID }
    }

    private var canSave: Bool {
        profile != nil
            && !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && defaultFieldsValidationMessage == nil
    }

    private var defaultFieldsValidationMessage: String? {
        do {
            try settings.validateDefaultFieldsJSON(defaultFieldsJSON)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func loadProfileDraft() {
        guard let profile else { return }
        profileName = profile.name
        projectKey = profile.projectKey
        defaultFieldsJSON = profile.defaultFieldsJSON
        message = ""
    }

    private func saveProfile() {
        guard var updatedProfile = profile else { return }
        updatedProfile.name = profileName
        updatedProfile.projectKey = projectKey
        updatedProfile.defaultFieldsJSON = defaultFieldsJSON

        do {
            try settings.updateProfile(updatedProfile)
            message = "Saved."
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }

    private func deleteProfile() {
        do {
            try settings.deleteProfile(id: profileID)
            dismiss()
        } catch {
            message = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func duplicateProfile() {
        do {
            let profile = try settings.duplicateProfile(id: profileID)
            message = "Duplicated as \(profile.name)."
        } catch {
            message = "Duplicate failed: \(error.localizedDescription)"
        }
    }
}

private struct JiraProjectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    let title: String
    let currentProjectKey: String
    let showsExistingProfileBadges: Bool
    let onSelect: (JiraProject) -> Void

    @State private var projects: [JiraProject] = []
    @State private var searchText = ""
    @State private var message = ""
    @State private var isLoadingProjects = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoadingProjects {
                        HStack {
                            ProgressView()
                            Text("Loading Jira projects...")
                                .foregroundStyle(.secondary)
                        }
                    } else if projects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No projects loaded.")
                                .foregroundStyle(.secondary)
                            Button("Load Jira Projects") {
                                Task { await loadProjects() }
                            }
                        }
                    } else {
                        ForEach(filteredProjectRows) { row in
                            projectRow(row.project)
                        }
                    }
                } footer: {
                    Text("Selecting a project updates this profile draft. Save the profile to persist it.")
                }

                if !message.isEmpty {
                    Section {
                        SettingsMessageView(message: message)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadProjects() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoadingProjects)
                    .accessibilityLabel("Refresh Jira Projects")
                }
            }
            .task {
                guard projects.isEmpty else { return }
                await loadProjects()
            }
        }
    }

    private func projectRow(_ project: JiraProject) -> some View {
        Button {
            onSelect(project)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Text(project.key)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showsExistingProfileBadges, existingProfile(for: project) != nil {
                    Text("Profile exists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if project.key.uppercased() == currentProjectKey.uppercased() {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var filteredProjectRows: [ProjectRow] {
        filteredProjects.map { ProjectRow(project: $0) }
    }

    private var filteredProjects: [JiraProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.lowercased().contains(query)
                || project.key.lowercased().contains(query)
        }
    }

    private func existingProfile(for project: JiraProject) -> JiraProfile? {
        settings.jiraProfiles.first {
            $0.projectKey.uppercased() == project.key.uppercased()
        }
    }

    private func loadProjects() async {
        guard hasJiraConnection else {
            message = "Fill in Jira Workspace URL, email, and API token first."
            return
        }

        isLoadingProjects = true
        message = ""
        defer { isLoadingProjects = false }

        do {
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: currentProjectKey.isEmpty ? (settings.activeJiraProfile?.projectKey ?? "") : currentProjectKey
            )
            projects = try await jira.fetchAccessibleProjects()
            message = projects.isEmpty
                ? "No accessible projects found for this account."
                : ""
        } catch {
            message = "Failed to load projects: \(error.localizedDescription)"
        }
    }

    private var hasJiraConnection: Bool {
        !settings.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct ProjectRow: Identifiable {
        let project: JiraProject

        var id: String { project.id }
    }
}

private struct JiraDefaultFieldsEditor: View {
    @EnvironmentObject private var settings: SettingsStore
    let projectKey: String
    @Binding var defaultFieldsJSON: String

    @State private var isAdvancedExpanded = false
    @State private var isFieldTemplateExpanded = false
    @State private var isLoadingFieldTemplate = false
    @State private var fieldTemplateProjectKey = ""
    @State private var fieldTemplateIssueTypes: [JiraIssueType] = []
    @State private var fieldTemplateFields: [JiraCreateFieldMetadata] = []
    @State private var projectVersions: [JiraVersion] = []
    @State private var selectedFieldTemplateIssueTypeID = ""
    @State private var fieldTemplateJSON = ""
    @State private var fieldTemplateMessage = ""

    private let issueTypeOptions = ["", "Bug", "Task", "Story", "Epic", "Sub-task"]
    private let priorityOptions = ["", "Highest", "High", "Medium", "Low", "Lowest"]
    private let guidedDefaultFieldKeys: Set<String> = ["issuetype", "priority", "labels"]
    private let appManagedDefaultFieldKeys: Set<String> = ["project", "summary", "description"]
    private let hiddenDefaultFieldKeys: Set<String> = ["project", "summary", "description"]
    private let versionModeOff = "off"
    private let versionModeAuto = "auto"
    private let versionModeManual = "manual"

    private struct VersionOption: Identifiable {
        let id: String
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if defaultFieldsObject.isEmpty, validationMessage == nil {
                Text("No additional default fields configured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoadingFieldTemplate {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading Jira fields...")
                        .foregroundStyle(.secondary)
                }
            }

            if fieldTemplateIssueTypes.isEmpty {
                Picker("Issue Type", selection: defaultFieldNameBinding(field: "issuetype")) {
                    ForEach(issueTypeOptions, id: \.self) { option in
                        Text(defaultFieldOptionTitle(option, emptyTitle: "App Default (Bug)"))
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .disabled(hasInvalidJSON || isLoadingFieldTemplate)
            } else {
                Picker("Issue Type", selection: issueTypeMetadataSelection) {
                    ForEach(fieldTemplateIssueTypes, id: \.id) { issueType in
                        Text(issueType.name)
                            .tag(issueType.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(hasInvalidJSON || isLoadingFieldTemplate)
            }

            if let priorityField, priorityField.allowedValues?.isEmpty == false {
                Picker("Priority", selection: priorityMetadataSelection) {
                    Text("Jira Default")
                        .tag("")
                    ForEach(priorityField.allowedValues ?? [], id: \.stableID) { value in
                        Text(value.label ?? "Unnamed")
                            .tag(value.stableID)
                    }
                }
                .pickerStyle(.menu)
                .disabled(hasInvalidJSON)
            } else {
                Picker("Priority", selection: defaultFieldNameBinding(field: "priority")) {
                    ForEach(priorityOptions, id: \.self) { option in
                        Text(defaultFieldOptionTitle(option, emptyTitle: "Jira Default"))
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .disabled(hasInvalidJSON)
            }

            TextField("Labels", text: labelsBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(hasInvalidJSON)

            if !visibleFieldMetadata.isEmpty || !fieldTemplateFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Project Fields")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if !hasFixVersionsMetadata {
                        automaticFixVersionsRow
                    }

                    ForEach(visibleFieldMetadata, id: \.fieldId) { field in
                        fieldMetadataRow(field)
                    }
                }
                .padding(.top, 4)
            }

            if !fieldTemplateJSON.isEmpty {
                Button("Copy Field Reference JSON") {
                    UIPasteboard.general.string = fieldTemplateJSON
                }
                .font(.caption)
            }

            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                TextEditor(text: $defaultFieldsJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 160)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("Use advanced JSON for custom Jira fields. The app sets project, summary, and description.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                HStack {
                    Text("Advanced JSON")
                    Spacer()
                    Text(advancedDefaultFieldsSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !fieldTemplateMessage.isEmpty {
                SettingsMessageView(message: fieldTemplateMessage)
            }
        }
        .task(id: projectKey) {
            await loadFieldTemplate()
        }
        .onChange(of: selectedFieldTemplateIssueTypeID) { _ in
            syncSelectedIssueTypeDefaultField()
            Task { await loadSelectedIssueTypeFields() }
        }
    }

    private var validationMessage: String? {
        do {
            try settings.validateDefaultFieldsJSON(defaultFieldsJSON)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var hasInvalidJSON: Bool {
        guard !trimmedDefaultFieldsJSON.isEmpty else { return false }
        return parsedDefaultFieldsObject == nil
    }

    private var trimmedDefaultFieldsJSON: String {
        defaultFieldsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedDefaultFieldsObject: [String: Any]? {
        guard !trimmedDefaultFieldsJSON.isEmpty,
              let data = trimmedDefaultFieldsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else {
            return trimmedDefaultFieldsJSON.isEmpty ? [:] : nil
        }
        return fields
    }

    private var defaultFieldsObject: [String: Any] {
        parsedDefaultFieldsObject ?? [:]
    }

    private var selectedIssueType: JiraIssueType? {
        fieldTemplateIssueTypes.first { $0.id == selectedFieldTemplateIssueTypeID }
    }

    private var issueTypeMetadataSelection: Binding<String> {
        Binding(
            get: { selectedFieldTemplateIssueTypeID },
            set: { selectedFieldTemplateIssueTypeID = $0 }
        )
    }

    private var priorityField: JiraCreateFieldMetadata? {
        fieldTemplateFields.first {
            $0.fieldId.lowercased() == "priority"
                || $0.name.caseInsensitiveCompare("Priority") == .orderedSame
        }
    }

    private var priorityMetadataSelection: Binding<String> {
        Binding(
            get: {
                guard let priorityField else { return "" }
                let values = priorityField.allowedValues ?? []
                let priority = defaultFieldsObject["priority"]

                if let object = priority as? [String: Any] {
                    if let id = object["id"] as? String,
                       let value = values.first(where: { $0.stableID == id || $0.id == id }) {
                        return value.stableID
                    }
                    if let name = object["name"] as? String,
                       let value = values.first(where: { $0.label?.caseInsensitiveCompare(name) == .orderedSame }) {
                        return value.stableID
                    }
                }

                if let name = priority as? String,
                   let value = values.first(where: { $0.label?.caseInsensitiveCompare(name) == .orderedSame }) {
                    return value.stableID
                }

                return ""
            },
            set: { valueID in
                updateDefaultFields { fields in
                    guard !valueID.isEmpty,
                          let value = priorityField?.allowedValues?.first(where: { $0.stableID == valueID }) else {
                        fields.removeValue(forKey: "priority")
                        return
                    }
                    fields["priority"] = allowedValueExample(value)
                }
            }
        )
    }

    private var visibleFieldMetadata: [JiraCreateFieldMetadata] {
        fieldTemplateFields.filter {
            !hiddenDefaultFieldKeys.contains($0.fieldId.lowercased())
                && !guidedDefaultFieldKeys.contains($0.fieldId.lowercased())
        }
    }

    private var hasFixVersionsMetadata: Bool {
        fieldTemplateFields.contains { $0.fieldId.lowercased() == "fixversions" }
    }

    private var automaticFixVersionsRow: some View {
        versionFieldRow(
            field: nil,
            fieldID: "fixVersions",
            name: "Fix versions",
            allowsOff: false,
            implicitAuto: true
        )
    }

    private func fieldMetadataRow(_ field: JiraCreateFieldMetadata) -> some View {
        if isVersionField(field) {
            return AnyView(
                versionFieldRow(
                    field: field,
                    fieldID: field.fieldId,
                    name: field.name,
                    allowsOff: field.fieldId.lowercased() != "fixversions",
                    implicitAuto: field.fieldId.lowercased() == "fixversions"
                )
            )
        }

        if field.allowedValues?.isEmpty == false {
            return AnyView(allowedValueFieldRow(field))
        }

        return AnyView(genericFieldMetadataRow(field))
    }

    private func genericFieldMetadataRow(_ field: JiraCreateFieldMetadata) -> some View {
        Button {
            toggleDefaultField(field)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.name)
                            .font(.footnote)
                            .fontWeight(.semibold)
                        Text(field.fieldId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    if field.required {
                        Text("Required")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if isAppManagedField(field) {
                        Text("Auto")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: isDefaultFieldSet(field) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(isDefaultFieldSet(field) ? Color.accentColor : Color.secondary)
                    }
                }

                if isAppManagedField(field) {
                    Text("Set automatically to \(JiraDynamicFieldValue.latestUnreleasedVersionLabel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isVersionField(field) {
                    Text("Tap to use \(JiraDynamicFieldValue.latestUnreleasedVersionLabel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(fieldTypeDescription(field))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let allowedValues = allowedValuesSummary(for: field) {
                    Text(allowedValues)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func allowedValueFieldRow(_ field: JiraCreateFieldMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.name)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(field.fieldId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if field.required {
                    Text("Required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Text("Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Value", selection: allowedValueSelection(field: field)) {
                    Text("Not Set")
                        .tag("")
                    ForEach(field.allowedValues ?? [], id: \.stableID) { value in
                        Text(value.label ?? value.stableID)
                            .tag(value.stableID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(hasInvalidJSON)
            }

            Text(fieldTypeDescription(field))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func versionFieldRow(
        field: JiraCreateFieldMetadata?,
        fieldID: String,
        name: String,
        allowsOff: Bool,
        implicitAuto: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(fieldID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if field?.required == true {
                    Text("Required")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Mode", selection: versionModeSelection(fieldID: fieldID, field: field, implicitAuto: implicitAuto)) {
                    if allowsOff {
                        Text("Not Set")
                            .tag(versionModeOff)
                    }
                    Text("Auto")
                        .tag(versionModeAuto)
                    Text("Manual")
                        .tag(versionModeManual)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            }

            if versionMode(fieldID: fieldID, implicitAuto: implicitAuto) == versionModeManual {
                if versionOptions(for: field).isEmpty {
                    Text("No Jira versions are available for manual selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Version")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Version", selection: manualVersionSelection(fieldID: fieldID, field: field)) {
                            ForEach(versionOptions(for: field)) { option in
                                Text(option.name)
                                    .tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
            } else if versionMode(fieldID: fieldID, implicitAuto: implicitAuto) == versionModeAuto {
                Text("Auto: \(JiraDynamicFieldValue.latestUnreleasedVersionLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let field {
                Text(fieldTypeDescription(field))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func isDefaultFieldSet(_ field: JiraCreateFieldMetadata) -> Bool {
        defaultFieldsObject[field.fieldId] != nil
    }

    private func isAppManagedField(_ field: JiraCreateFieldMetadata) -> Bool {
        appManagedDefaultFieldKeys.contains(field.fieldId.lowercased())
    }

    private func allowedValueSelection(field: JiraCreateFieldMetadata) -> Binding<String> {
        Binding(
            get: {
                selectedAllowedValueID(for: field) ?? ""
            },
            set: { valueID in
                let selectedValue = field.allowedValues?.first { $0.stableID == valueID }
                updateDefaultFields { fields in
                    guard let selectedValue else {
                        fields.removeValue(forKey: field.fieldId)
                        return
                    }

                    fields[field.fieldId] = allowedFieldValue(field: field, value: selectedValue)
                }

                if let selectedValue {
                    fieldTemplateMessage = "\(field.name) uses \(selectedValue.label ?? selectedValue.stableID)."
                } else {
                    fieldTemplateMessage = "Removed \(field.name) from Advanced JSON."
                }
                isAdvancedExpanded = true
            }
        )
    }

    private func selectedAllowedValueID(for field: JiraCreateFieldMetadata) -> String? {
        guard let value = defaultFieldsObject[field.fieldId],
              let allowedValues = field.allowedValues,
              !allowedValues.isEmpty else {
            return nil
        }

        return matchingAllowedValueID(in: value, allowedValues: allowedValues)
    }

    private func matchingAllowedValueID(in value: Any, allowedValues: [JiraFieldAllowedValue]) -> String? {
        if let array = value as? [Any] {
            return array.compactMap { matchingAllowedValueID(in: $0, allowedValues: allowedValues) }.first
        }

        if let object = value as? [String: Any] {
            let candidates = ["id", "accountId", "key", "name", "value", "displayName"]
                .compactMap { object[$0] as? String }
            return matchingAllowedValueID(candidates: candidates, allowedValues: allowedValues)
        }

        if let string = value as? String {
            return matchingAllowedValueID(candidates: [string], allowedValues: allowedValues)
        }

        return nil
    }

    private func matchingAllowedValueID(
        candidates: [String],
        allowedValues: [JiraFieldAllowedValue]
    ) -> String? {
        for candidate in candidates {
            for allowedValue in allowedValues where allowedValue.matches(candidate) {
                return allowedValue.stableID
            }
        }
        return nil
    }

    private func allowedFieldValue(field: JiraCreateFieldMetadata, value: JiraFieldAllowedValue) -> Any {
        let value = allowedValueExample(value)
        if field.schema?.type?.lowercased() == "array" {
            return [value]
        }
        return value
    }

    private func versionMode(fieldID: String, implicitAuto: Bool) -> String {
        guard let value = defaultFieldsObject[fieldID] else {
            return implicitAuto ? versionModeAuto : versionModeOff
        }
        return containsLatestUnreleasedVersionPlaceholder(value) ? versionModeAuto : versionModeManual
    }

    private func versionModeSelection(
        fieldID: String,
        field: JiraCreateFieldMetadata?,
        implicitAuto: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                versionMode(fieldID: fieldID, implicitAuto: implicitAuto)
            },
            set: { mode in
                switch mode {
                case versionModeOff:
                    updateDefaultFields { fields in
                        fields.removeValue(forKey: fieldID)
                    }
                    fieldTemplateMessage = "Removed \(field?.name ?? fieldID) from Advanced JSON."
                case versionModeAuto:
                    updateDefaultFields { fields in
                        fields[fieldID] = versionFieldValue(
                            fieldID: fieldID,
                            field: field,
                            value: latestUnreleasedVersionPlaceholder()
                        )
                    }
                    fieldTemplateMessage = "\(field?.name ?? fieldID) uses \(JiraDynamicFieldValue.latestUnreleasedVersionLabel)."
                case versionModeManual:
                    let options = versionOptions(for: field)
                    let selectedID = currentManualVersionID(fieldID: fieldID) ?? options.first?.id
                    guard let selectedID,
                          let option = options.first(where: { $0.id == selectedID }) else {
                        fieldTemplateMessage = "No Jira versions are available for \(field?.name ?? fieldID)."
                        return
                    }
                    updateDefaultFields { fields in
                        fields[fieldID] = versionFieldValue(
                            fieldID: fieldID,
                            field: field,
                            value: [
                                "id": option.id,
                                "name": option.name
                            ]
                        )
                    }
                    fieldTemplateMessage = "\(field?.name ?? fieldID) uses \(option.name)."
                default:
                    return
                }
                isAdvancedExpanded = true
            }
        )
    }

    private func manualVersionSelection(
        fieldID: String,
        field: JiraCreateFieldMetadata?
    ) -> Binding<String> {
        Binding(
            get: {
                currentManualVersionID(fieldID: fieldID) ?? versionOptions(for: field).first?.id ?? ""
            },
            set: { versionID in
                guard let option = versionOptions(for: field).first(where: { $0.id == versionID }) else { return }
                updateDefaultFields { fields in
                    fields[fieldID] = versionFieldValue(
                        fieldID: fieldID,
                        field: field,
                        value: [
                            "id": option.id,
                            "name": option.name
                        ]
                    )
                }
                fieldTemplateMessage = "\(field?.name ?? fieldID) uses \(option.name)."
            }
        )
    }

    private func versionOptions(for field: JiraCreateFieldMetadata?) -> [VersionOption] {
        if let allowedValues = field?.allowedValues, !allowedValues.isEmpty {
            return allowedValues.compactMap { value in
                guard let label = value.label else { return nil }
                return VersionOption(id: value.stableID, name: label)
            }
        }

        return projectVersions
            .filter { ($0.archived ?? false) == false }
            .map { VersionOption(id: $0.id, name: $0.name) }
    }

    private func currentManualVersionID(fieldID: String) -> String? {
        guard let value = defaultFieldsObject[fieldID],
              !containsLatestUnreleasedVersionPlaceholder(value) else {
            return nil
        }
        return versionID(from: value)
    }

    private func versionID(from value: Any) -> String? {
        if let object = value as? [String: Any] {
            return object["id"] as? String
        }

        if let array = value as? [Any] {
            return array.compactMap(versionID).first
        }

        return nil
    }

    private func containsLatestUnreleasedVersionPlaceholder(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if object["id"] as? String == JiraDynamicFieldValue.latestUnreleasedVersionID {
                return true
            }
            return object.values.contains { containsLatestUnreleasedVersionPlaceholder($0) }
        }

        if let array = value as? [Any] {
            return array.contains { containsLatestUnreleasedVersionPlaceholder($0) }
        }

        return false
    }

    private func versionFieldValue(
        fieldID: String,
        field: JiraCreateFieldMetadata?,
        value: [String: String]
    ) -> Any {
        if fieldID.lowercased() == "versions"
            || fieldID.lowercased() == "fixversions"
            || field?.schema?.type?.lowercased() == "array" {
            return [value]
        }
        return value
    }

    private func toggleDefaultField(_ field: JiraCreateFieldMetadata) {
        if isAppManagedField(field) {
            fieldTemplateMessage = "\(field.name) is set automatically to \(JiraDynamicFieldValue.latestUnreleasedVersionLabel) when creating issues."
            return
        }

        if isDefaultFieldSet(field) {
            updateDefaultFields { fields in
                fields.removeValue(forKey: field.fieldId)
            }
            fieldTemplateMessage = "Removed \(field.name) from Advanced JSON."
        } else {
            addDefaultField(field)
        }
        isAdvancedExpanded = true
    }

    private func addDefaultField(_ field: JiraCreateFieldMetadata) {
        guard let issueType = selectedIssueType ?? fieldTemplateIssueTypes.first else { return }
        let normalizedProjectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updateDefaultFields { fields in
            fields[field.fieldId] = fieldExampleValue(
                projectKey: normalizedProjectKey,
                issueType: issueType,
                field: field
            )
        }
        fieldTemplateMessage = "Added \(field.name) to Advanced JSON."
    }

    private func allowedValuesSummary(for field: JiraCreateFieldMetadata) -> String? {
        guard let allowedValues = field.allowedValues, !allowedValues.isEmpty else { return nil }
        let labels = allowedValues
            .prefix(5)
            .compactMap(\.label)
            .joined(separator: ", ")

        if allowedValues.count > 5 {
            return "\(labels), +\(allowedValues.count - 5) more"
        }
        return labels
    }

    private var labelsBinding: Binding<String> {
        Binding(
            get: {
                let labels = defaultFieldsObject["labels"]
                if let values = labels as? [String] {
                    return values.joined(separator: ", ")
                }
                if let values = labels as? [Any] {
                    return values.compactMap { $0 as? String }.joined(separator: ", ")
                }
                return labels as? String ?? ""
            },
            set: { value in
                updateDefaultFields { fields in
                    let labels = parsedLabels(from: value)
                    if labels.isEmpty {
                        fields.removeValue(forKey: "labels")
                    } else {
                        fields["labels"] = labels
                    }
                }
            }
        )
    }

    private var advancedDefaultFieldsSummary: String {
        let count = defaultFieldsObject.keys.filter { !guidedDefaultFieldKeys.contains($0.lowercased()) }.count
        if count == 0 {
            return "No custom fields"
        }
        return count == 1 ? "1 custom field" : "\(count) custom fields"
    }

    private func defaultFieldNameBinding(field: String) -> Binding<String> {
        Binding(
            get: {
                let fields = defaultFieldsObject
                if let object = fields[field] as? [String: Any],
                   let name = object["name"] as? String {
                    return name
                }
                return fields[field] as? String ?? ""
            },
            set: { value in
                updateDefaultFields { fields in
                    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedValue.isEmpty {
                        fields.removeValue(forKey: field)
                    } else {
                        fields[field] = ["name": trimmedValue]
                    }
                }
            }
        )
    }

    private func updateDefaultFields(_ update: (inout [String: Any]) -> Void) {
        var fields = defaultFieldsObject
        update(&fields)
        defaultFieldsJSON = serializedDefaultFields(fields)
    }

    private func serializedDefaultFields(_ fields: [String: Any]) -> String {
        guard !fields.isEmpty,
              JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func defaultFieldOptionTitle(_ option: String, emptyTitle: String) -> String {
        option.isEmpty ? emptyTitle : option
    }

    private func parsedLabels(from value: String) -> [String] {
        var labels: [String] = []
        var seen: Set<String> = []
        let rawLabels = value.split { character in
            character == "," || character.isWhitespace || character.isNewline
        }

        for rawLabel in rawLabels {
            let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !seen.contains(label) else { continue }
            seen.insert(label)
            labels.append(label)
        }

        return labels
    }

    private var hasJiraConnection: Bool {
        !settings.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadFieldTemplate() async {
        let normalizedProjectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedProjectKey.isEmpty else { return }
        guard hasJiraConnection else {
            fieldTemplateMessage = "Fill in Jira Workspace URL, email, and API token first."
            return
        }

        isLoadingFieldTemplate = true
        fieldTemplateMessage = ""
        defer { isLoadingFieldTemplate = false }

        do {
            if fieldTemplateProjectKey != normalizedProjectKey {
                fieldTemplateProjectKey = normalizedProjectKey
                fieldTemplateIssueTypes = []
                fieldTemplateFields = []
                projectVersions = []
                selectedFieldTemplateIssueTypeID = ""
                fieldTemplateJSON = ""
            }

            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: normalizedProjectKey
            )

            if fieldTemplateIssueTypes.isEmpty {
                fieldTemplateIssueTypes = try await jira.fetchCreateIssueTypes(projectKey: normalizedProjectKey)
                selectedFieldTemplateIssueTypeID = preferredIssueTypeID(from: fieldTemplateIssueTypes)
            }

            if projectVersions.isEmpty {
                projectVersions = try await jira.fetchProjectVersions()
            }

            guard let issueType = fieldTemplateIssueTypes.first(where: { $0.id == selectedFieldTemplateIssueTypeID }) else {
                fieldTemplateJSON = ""
                fieldTemplateMessage = "No issue types found for \(normalizedProjectKey)."
                return
            }

            syncSelectedIssueTypeDefaultField()
            let fields = try await jira.fetchCreateFields(projectKey: normalizedProjectKey, issueTypeId: issueType.id)
            fieldTemplateFields = fields
            fieldTemplateJSON = fieldReferenceTemplateJSON(projectKey: normalizedProjectKey, issueType: issueType, fields: fields)
            fieldTemplateMessage = ""
        } catch {
            fieldTemplateFields = []
            fieldTemplateJSON = ""
            fieldTemplateMessage = "Failed to load field template: \(error.localizedDescription)"
        }
    }

    private func loadSelectedIssueTypeFields() async {
        let normalizedProjectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedProjectKey.isEmpty,
              hasJiraConnection,
              let issueType = selectedIssueType else {
            return
        }

        isLoadingFieldTemplate = true
        fieldTemplateMessage = ""
        defer { isLoadingFieldTemplate = false }

        do {
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: normalizedProjectKey
            )
            if projectVersions.isEmpty {
                projectVersions = try await jira.fetchProjectVersions()
            }
            let fields = try await jira.fetchCreateFields(projectKey: normalizedProjectKey, issueTypeId: issueType.id)
            fieldTemplateFields = fields
            fieldTemplateJSON = fieldReferenceTemplateJSON(projectKey: normalizedProjectKey, issueType: issueType, fields: fields)
        } catch {
            fieldTemplateFields = []
            fieldTemplateJSON = ""
            fieldTemplateMessage = "Failed to load fields for \(issueType.name): \(error.localizedDescription)"
        }
    }

    private func syncSelectedIssueTypeDefaultField() {
        guard let issueType = selectedIssueType else { return }
        updateDefaultFields { fields in
            fields["issuetype"] = [
                "id": issueType.id,
                "name": issueType.name
            ]
        }
    }

    private func preferredIssueTypeID(from issueTypes: [JiraIssueType]) -> String {
        let fields = defaultFieldsObject
        if let object = fields["issuetype"] as? [String: Any] {
            if let id = object["id"] as? String,
               let issueType = issueTypes.first(where: { $0.id == id }) {
                return issueType.id
            }
            if let name = object["name"] as? String,
               let issueType = issueTypes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return issueType.id
            }
        }

        if let name = fields["issuetype"] as? String,
           let issueType = issueTypes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return issueType.id
        }

        if let bug = issueTypes.first(where: { $0.name.caseInsensitiveCompare("Bug") == .orderedSame }) {
            return bug.id
        }

        return issueTypes.first?.id ?? ""
    }

    private func fieldReferenceTemplateJSON(projectKey: String, issueType: JiraIssueType, fields: [JiraCreateFieldMetadata]) -> String {
        var referenceFields: [String: Any] = [:]
        for field in fields {
            referenceFields[field.fieldId] = fieldReferenceEntry(
                projectKey: projectKey,
                issueType: issueType,
                field: field
            )
        }

        let reference: [String: Any] = [
            "projectKey": projectKey,
            "issueType": [
                "id": issueType.id,
                "name": issueType.name
            ],
            "fields": referenceFields
        ]

        guard JSONSerialization.isValidJSONObject(reference),
              let data = try? JSONSerialization.data(withJSONObject: reference, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func fieldReferenceEntry(projectKey: String, issueType: JiraIssueType, field: JiraCreateFieldMetadata) -> [String: Any] {
        var entry: [String: Any] = [
            "name": field.name,
            "required": field.required,
            "type": fieldTypeDescription(field),
            "example": fieldExampleValue(projectKey: projectKey, issueType: issueType, field: field)
        ]

        if appManagedDefaultFieldKeys.contains(field.fieldId.lowercased()) {
            entry["appManaged"] = true
        }

        if let operations = field.operations, !operations.isEmpty {
            entry["operations"] = operations
        }

        if let hasDefaultValue = field.hasDefaultValue {
            entry["hasDefaultValue"] = hasDefaultValue
        }

        if let allowedValues = field.allowedValues, !allowedValues.isEmpty {
            entry["allowedValues"] = allowedValues.prefix(25).map(allowedValueReference)
            if allowedValues.count > 25 {
                entry["allowedValuesTotal"] = allowedValues.count
            }
        }

        return entry
    }

    private func fieldTypeDescription(_ field: JiraCreateFieldMetadata) -> String {
        guard let schema = field.schema else { return "unknown" }
        var parts: [String] = []

        if let type = schema.type {
            if let items = schema.items {
                parts.append("\(type)<\(items)>")
            } else {
                parts.append(type)
            }
        }

        if let system = schema.system {
            parts.append("system:\(system)")
        }

        if let custom = schema.custom {
            parts.append("custom:\(custom)")
        }

        if let customId = schema.customId {
            parts.append("customId:\(customId)")
        }

        return parts.isEmpty ? "unknown" : parts.joined(separator: " | ")
    }

    private func fieldExampleValue(projectKey: String, issueType: JiraIssueType, field: JiraCreateFieldMetadata) -> Any {
        let fieldID = field.fieldId.lowercased()

        if fieldID == "project" {
            return ["key": projectKey]
        }

        if fieldID == "summary" {
            return "<generated summary>"
        }

        if fieldID == "description" {
            return "<generated ADF description>"
        }

        if fieldID == "issuetype" {
            return [
                "id": issueType.id,
                "name": issueType.name
            ]
        }

        if fieldID == "fixversions" {
            return [latestUnreleasedVersionPlaceholder()]
        }

        if isVersionField(field) {
            let placeholder = latestUnreleasedVersionPlaceholder()
            if field.schema?.type?.lowercased() == "array" {
                return [placeholder]
            }
            return placeholder
        }

        if let allowedValue = field.allowedValues?.first {
            let value = allowedValueExample(allowedValue)
            if field.schema?.type?.lowercased() == "array" {
                return [value]
            }
            return value
        }

        let placeholder = "<\(field.name)>"
        let type = field.schema?.type?.lowercased()
        let items = field.schema?.items?.lowercased()

        switch type {
        case "array":
            if items == "user" {
                return [["id": "<accountId>"]]
            }
            if items == "component" || items == "version" {
                return [["id": "<\(field.name) id>"]]
            }
            return [placeholder]
        case "number":
            return 0
        case "date":
            return "YYYY-MM-DD"
        case "datetime":
            return "YYYY-MM-DDThh:mm:ss.000+0000"
        case "user":
            return ["id": "<accountId>"]
        case "option":
            return ["value": placeholder]
        case "component", "version", "priority":
            return ["id": "<\(field.name) id>"]
        default:
            return placeholder
        }
    }

    private func isVersionField(_ field: JiraCreateFieldMetadata) -> Bool {
        let fieldID = field.fieldId.lowercased()
        let schemaType = field.schema?.type?.lowercased()
        let schemaItems = field.schema?.items?.lowercased()
        let schemaSystem = field.schema?.system?.lowercased()

        return fieldID == "versions"
            || fieldID == "fixversions"
            || schemaType == "version"
            || schemaItems == "version"
            || schemaSystem == "versions"
            || schemaSystem == "fixversions"
    }

    private func latestUnreleasedVersionPlaceholder() -> [String: String] {
        [
            "id": JiraDynamicFieldValue.latestUnreleasedVersionID,
            "name": JiraDynamicFieldValue.latestUnreleasedVersionLabel
        ]
    }

    private func allowedValueReference(_ value: JiraFieldAllowedValue) -> [String: String] {
        var reference: [String: String] = [:]
        if let id = value.id {
            reference["id"] = id
        }
        if let key = value.key {
            reference["key"] = key
        }
        if let name = value.name {
            reference["name"] = name
        }
        if let value = value.value {
            reference["value"] = value
        }
        if let accountId = value.accountId {
            reference["accountId"] = accountId
        }
        if let displayName = value.displayName {
            reference["displayName"] = displayName
        }
        return reference
    }

    private func allowedValueExample(_ value: JiraFieldAllowedValue) -> [String: String] {
        var example: [String: String] = [:]
        if let id = value.id {
            example["id"] = id
        }
        if let accountId = value.accountId {
            example["id"] = accountId
        }
        if let name = value.name {
            example["name"] = name
        }
        if let value = value.value {
            example["value"] = value
        }
        if example.isEmpty, let label = value.label {
            example["value"] = label
        }
        return example
    }
}

private struct SettingsMessageView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Copy Message") {
                UIPasteboard.general.string = message
            }
            .font(.caption)
        }
    }
}

private extension JiraFieldAllowedValue {
    var stableID: String {
        id ?? accountId ?? key ?? name ?? value ?? displayName ?? "unnamed"
    }

    func matches(_ candidate: String) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }

        let exactValues = [stableID, id, accountId, key].compactMap { $0 }
        if exactValues.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return true
        }

        let labelValues = [name, value, displayName, label].compactMap { $0 }
        return labelValues.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
    }
}
