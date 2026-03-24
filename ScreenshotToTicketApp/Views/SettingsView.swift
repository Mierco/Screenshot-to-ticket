import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var saveMessage = ""
    @State private var isLoadingProjects = false
    @State private var isTestingAuth = false
    @State private var projectMessage = ""
    @State private var authMessage = ""
    @State private var projects: [JiraProject] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Jira") {
                    TextField("Workspace URL", text: $settings.workspaceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Project Key", text: $settings.projectKey)
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(authMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Button("Copy Message") {
                                UIPasteboard.general.string = authMessage
                            }
                            .font(.caption)
                        }
                    }

                    Button {
                        Task { await loadProjects() }
                    } label: {
                        if isLoadingProjects {
                            ProgressView()
                        } else {
                            Text("Load Available Projects")
                        }
                    }
                    .disabled(isLoadingProjects || settings.workspaceURL.isEmpty || settings.jiraEmail.isEmpty || settings.jiraApiToken.isEmpty)

                    if !projects.isEmpty {
                        Picker("Available Projects", selection: $settings.projectKey) {
                            ForEach(projects) { project in
                                Text("\(project.key) - \(project.name)")
                                    .tag(project.key)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if !projectMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(projectMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Button("Copy Message") {
                                UIPasteboard.general.string = projectMessage
                            }
                            .font(.caption)
                        }
                    }
                }

                Section("OpenAI") {
                    SecureField("OpenAI API Key", text: $settings.openAIKey)
                    TextField("Model ID", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saveMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Button("Copy Message") {
                                UIPasteboard.general.string = saveMessage
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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
                projectKey: settings.projectKey
            )
            let fetched = try await jira.fetchAccessibleProjects()
            projects = fetched

            if let current = fetched.first(where: { $0.key == settings.projectKey }) {
                settings.projectKey = current.key
            } else if let first = fetched.first {
                settings.projectKey = first.key
            }

            projectMessage = fetched.isEmpty
                ? "No accessible projects found for this account."
                : "Loaded \(fetched.count) projects."
        } catch {
            projectMessage = "Failed to load projects: \(error.localizedDescription)"
        }
    }

    private func testJiraAccess() async {
        isTestingAuth = true
        authMessage = ""
        defer { isTestingAuth = false }

        do {
            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: settings.projectKey
            )

            let me = try await jira.fetchCurrentUser()
            let display = me.emailAddress ?? me.displayName

            if settings.projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authMessage = "Auth OK as \(display). Enter a project key to test project access."
                return
            }

            try await jira.validateProjectAccess(projectKey: settings.projectKey.uppercased())
            authMessage = "Auth OK as \(display). Project \(settings.projectKey.uppercased()) is accessible."
        } catch {
            authMessage = "Access test failed: \(error.localizedDescription)"
        }
    }
}
