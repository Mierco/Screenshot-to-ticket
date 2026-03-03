import PhotosUI
import SwiftUI
import UIKit

struct MainView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var vm = MainViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Media") {
                    PhotosPicker(
                        selection: $vm.selectedItems,
                        maxSelectionCount: 3,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Text("Select up to 3 images or videos")
                    }

                    Text("Selected: \(vm.selectedItems.count)")
                        .foregroundStyle(.secondary)
                }

                Section("Hints / Instructions") {
                    TextEditor(text: $vm.hintText)
                        .frame(minHeight: 120)
                }

                Section("Submit") {
                    Button {
                        Task { await vm.submit(settings: settings) }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create Jira Bug")
                        }
                    }
                    .disabled(vm.isSubmitting)

                    if !vm.status.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vm.status)
                                .font(.footnote)
                                .textSelection(.enabled)
                            if let issueURL = vm.issueURL {
                                Link("Open Jira Issue", destination: issueURL)
                                    .font(.footnote)
                                Text(issueURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Button("Copy Message") {
                                UIPasteboard.general.string = vm.status
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Screenshot to Jira")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
        }
    }
}
