import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @State private var saveMessage = ""
    @State private var isLoadingProjects = false
    @State private var isTestingAuth = false
    @State private var projectMessage = ""
    @State private var authMessage = ""
    @State private var projects: [JiraProject] = []
    @State private var selectedProjectKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Jira") {
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
                    .disabled(isTestingAuth || settings.workspaceURL.isEmpty || settings.jiraEmail.isEmpty || settings.jiraApiToken.isEmpty)

                    if !authMessage.isEmpty {
                        messageView(authMessage)
                    }

                }

                Section("Jira Profiles") {
                    Picker("Active Profile", selection: $settings.activeJiraProfileID) {
                        ForEach(settings.jiraProfiles) { profile in
                            Text("\(profile.name) (\(profile.projectKey))")
                                .tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        Task { await loadProjects() }
                    } label: {
                        if isLoadingProjects {
                            ProgressView()
                        } else {
                            Label(projects.isEmpty ? "Add Profile from Jira Project" : "Refresh Jira Projects", systemImage: "plus.circle")
                        }
                    }
                    .disabled(isLoadingProjects || settings.workspaceURL.isEmpty || settings.jiraEmail.isEmpty || settings.jiraApiToken.isEmpty)

                    if !projects.isEmpty {
                        Picker("Project to Add", selection: $selectedProjectKey) {
                            ForEach(projects) { project in
                                Text("\(project.key) - \(project.name)")
                                    .tag(project.key)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            activateSelectedProject()
                        } label: {
                            Label(selectedProjectAlreadyHasProfile ? "Activate Existing Profile" : "Create Profile from Selected Project", systemImage: selectedProjectAlreadyHasProfile ? "checkmark.circle" : "plus.circle")
                        }
                        .disabled(selectedProjectKey.isEmpty)
                    }

                    if !projectMessage.isEmpty {
                        messageView(projectMessage)
                    }

                    if let profile = settings.activeJiraProfile {
                        Divider()

                        TextField("Profile Name", text: activeProfileBinding(\.name))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        LabeledContent("Project Key", value: profile.projectKey)

                        TextEditor(text: activeProfileBinding(\.defaultFieldsJSON))
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 160)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("Default fields must be a Jira fields JSON object. The app sets project, summary, description, and fixVersions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Delete Active Profile", role: .destructive) {
                            settings.deleteActiveJiraProfile()
                            saveMessage = ""
                        }
                        .disabled(settings.jiraProfiles.count <= 1)
                    } else {
                        Text("No Jira profiles configured.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                    Button("Save") {
                        do {
                            try settings.save()
                            saveMessage = "Saved."
                        } catch {
                            saveMessage = "Save failed: \(error.localizedDescription)"
                        }
                    }

                    if !saveMessage.isEmpty {
                        messageView(saveMessage)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func messageView(_ message: String) -> some View {
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

    private func activeProfileBinding(_ keyPath: WritableKeyPath<JiraProfile, String>) -> Binding<String> {
        Binding(
            get: {
                settings.activeJiraProfile?[keyPath: keyPath] ?? ""
            },
            set: { value in
                settings.updateActiveJiraProfile { profile in
                    profile[keyPath: keyPath] = value
                }
            }
        )
    }

    private var selectedProjectAlreadyHasProfile: Bool {
        settings.jiraProfiles.contains {
            $0.projectKey.uppercased() == selectedProjectKey.uppercased()
        }
    }

    private func loadProjects() async {
        isLoadingProjects = true
        projectMessage = ""
        defer { isLoadingProjects = false }

        do {
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: settings.activeJiraProfile?.projectKey ?? "TMNEWS"
            )
            let fetched = try await jira.fetchAccessibleProjects()
            projects = fetched

            let activeProjectKey = settings.activeJiraProfile?.projectKey.uppercased()
            if let activeProjectKey,
               let current = fetched.first(where: { $0.key.uppercased() == activeProjectKey }) {
                selectedProjectKey = current.key
            } else {
                selectedProjectKey = fetched.first?.key ?? ""
            }

            projectMessage = fetched.isEmpty
                ? "No accessible projects found for this account."
                : "Loaded \(fetched.count) projects. Choose one below to create or activate a profile."
        } catch {
            projectMessage = "Failed to load projects: \(error.localizedDescription)"
        }
    }

    private func activateSelectedProject() {
        guard let project = projects.first(where: { $0.key == selectedProjectKey }) else { return }
        let alreadyExists = settings.jiraProfiles.contains {
            $0.projectKey.uppercased() == project.key.uppercased()
        }

        settings.activateOrCreateProfile(from: project)
        projectMessage = alreadyExists
            ? "Activated profile for \(project.key)."
            : "Added profile for \(project.key). Tap Save to persist it."
        saveMessage = ""
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
