import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainViewModel: ObservableObject {
    struct Attachment {
        let data: Data
        let fileName: String
        let contentType: String
        let aiPreviewJPEG: Data?
    }

    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var hintText: String = ""
    @Published var status: String = ""
    @Published var issueURL: URL?
    @Published var isSubmitting = false

    func submit(settings: SettingsStore) async {
        issueURL = nil
        guard settings.isConfigured else {
            status = "Fill Jira/OpenAI credentials in Settings."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            status = "Loading media..."
            let attachments = try await loadAttachments(from: Array(selectedItems.prefix(3)))
            let aiImages = attachments.compactMap(\.aiPreviewJPEG)
            guard !aiImages.isEmpty else {
                status = "Select at least one image or video."
                return
            }

            status = "Drafting ticket text with AI..."
            let openAI = OpenAIClient(apiKey: settings.openAIKey, model: settings.model)
            let draft = try await openAI.draftTicket(from: aiImages, userHint: hintText)

            let notes = hintText.isEmpty ? "" : "\n\nReporter notes:\n\(hintText)"
            let description = draft.description + notes

            let jira = JiraClient(
                workspaceURL: settings.workspaceURL,
                email: settings.jiraEmail,
                apiToken: settings.jiraApiToken,
                projectKey: settings.projectKey
            )

            status = "Resolving fix version..."
            let fixVersion = try await jira.fetchBiggestUnreleasedVersion()

            status = "Creating Jira issue..."
            let issue = try await jira.createIssue(
                summary: draft.summary,
                description: description,
                fixVersionId: fixVersion?.id
            )

            status = "Uploading attachments..."
            for attachment in attachments {
                try await jira.attachFile(
                    issueKey: issue.key,
                    data: attachment.data,
                    fileName: attachment.fileName,
                    contentType: attachment.contentType
                )
            }

            let base = settings.workspaceURL.hasSuffix("/") ? String(settings.workspaceURL.dropLast()) : settings.workspaceURL
            let issueLink = "\(base)/browse/\(issue.key)"
            issueURL = URL(string: issueLink)
            status = "Done: \(issue.key)"
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func loadAttachments(from items: [PhotosPickerItem]) async throws -> [Attachment] {
        var result: [Attachment] = []
        for (index, item) in items.enumerated() {
            if let data = try await item.loadTransferable(type: Data.self) {
                let isVideo = item.supportedContentTypes.contains {
                    $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .audiovisualContent)
                }
                if isVideo {
                    result.append(
                        Attachment(
                            data: data,
                            fileName: "attachment-\(index + 1).mp4",
                            contentType: "video/mp4",
                            aiPreviewJPEG: VideoThumbnail.jpegPreview(from: data)
                        )
                    )
                } else {
                    let jpeg = ImageCompression.compressedJPEG(data)
                    result.append(
                        Attachment(
                            data: jpeg,
                            fileName: "attachment-\(index + 1).jpg",
                            contentType: "image/jpeg",
                            aiPreviewJPEG: jpeg
                        )
                    )
                }
            }
        }
        return result
    }
}
