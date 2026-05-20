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

                        if let activeProfile = settings.activeJiraProfile {
                            NavigationLink {
                                JiraProfileDetailView(profileID: activeProfile.id)
                                    .environmentObject(settings)
                            } label: {
                                Label("Edit Selected Profile", systemImage: "slider.horizontal.3")
                            }
                        }
                    }

                    Button {
                        isAddingProfile = true
                    } label: {
                        Label("Add Profile", systemImage: "plus.circle")
                    }
                    .disabled(!hasJiraConnection)
                } header: {
                    Text("Jira Profile")
                } footer: {
                    if !hasJiraConnection {
                        Text("Add your Jira connection details before creating profiles.")
                    } else {
                        Text("Choose the active profile here. New profiles open in a separate full-screen flow.")
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
                projectKey: activeProjectKey.isEmpty ? "TMNEWS" : activeProjectKey
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
                projectKey: settings.activeJiraProfile?.projectKey ?? "TMNEWS"
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
    @State private var defaultFieldsJSON = "{}"
    @State private var message = ""
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Form {
            if let profile {
                Section("Profile") {
                    TextField("Profile Name", text: $profileName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    LabeledContent("Project Key", value: profile.projectKey)
                }

                Section("Default Fields") {
                    JiraDefaultFieldsEditor(projectKey: profile.projectKey, defaultFieldsJSON: $defaultFieldsJSON)
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
                    .disabled(settings.jiraProfiles.count <= 1)
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
            Text("At least one profile must remain.")
        }
        .onAppear(perform: loadProfileDraft)
        .onChange(of: profileID) { _ in
            loadProfileDraft()
        }
    }

    private var profile: JiraProfile? {
        settings.jiraProfiles.first { $0.id == profileID }
    }

    private var canSave: Bool {
        profile != nil
            && !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        defaultFieldsJSON = profile.defaultFieldsJSON
        message = ""
    }

    private func saveProfile() {
        guard var updatedProfile = profile else { return }
        updatedProfile.name = profileName
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
    @State private var selectedFieldTemplateIssueTypeID = ""
    @State private var fieldTemplateJSON = ""
    @State private var fieldTemplateMessage = ""

    private let issueTypeOptions = ["", "Bug", "Task", "Story", "Epic", "Sub-task"]
    private let priorityOptions = ["", "Highest", "High", "Medium", "Low", "Lowest"]
    private let guidedDefaultFieldKeys: Set<String> = ["issuetype", "priority", "labels"]
    private let appManagedDefaultFieldKeys: Set<String> = ["project", "summary", "description", "fixversions"]

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

            if !visibleFieldMetadata.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Project Fields")
                        .font(.subheadline)
                        .fontWeight(.semibold)

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

                Text("Use advanced JSON for custom Jira fields. The app sets project, summary, description, and fixVersions.")
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
            !appManagedDefaultFieldKeys.contains($0.fieldId.lowercased())
        }
    }

    private func fieldMetadataRow(_ field: JiraCreateFieldMetadata) -> some View {
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
            }

            Text(fieldTypeDescription(field))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let allowedValues = allowedValuesSummary(for: field) {
                Text(allowedValues)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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
            return [["id": "<version id>"]]
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
}
