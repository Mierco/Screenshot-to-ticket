import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewModel: ObservableObject {
    struct Attachment {
        let data: Data
        let fileName: String
        let contentType: String
        let aiPreviewJPEG: Data?
    }

    enum AnnotationShape: String, CaseIterable, Identifiable {
        case freehand = "Freehand"
        case circle = "Circle"
        case rectangle = "Rectangle"
        case arrow = "Arrow"

        var id: String { rawValue }
    }

    enum AnnotationColor: String, CaseIterable, Identifiable {
        case red = "Red"
        case yellow = "Yellow"
        case green = "Green"
        case blue = "Blue"
        case orange = "Orange"

        var id: String { rawValue }

        var swatch: Color {
            switch self {
            case .red: return .red
            case .yellow: return .yellow
            case .green: return .green
            case .blue: return .blue
            case .orange: return .orange
            }
        }

        var uiColor: UIColor {
            switch self {
            case .red: return .systemRed
            case .yellow: return .systemYellow
            case .green: return .systemGreen
            case .blue: return .systemBlue
            case .orange: return .systemOrange
            }
        }
    }

    struct AnnotationMark: Identifiable {
        let id = UUID()
        var points: [CGPoint] // normalized to [0,1]
        let shape: AnnotationShape
        let color: AnnotationColor
    }

    struct LoadedMedia: Identifiable {
        enum Kind {
            case image
            case video
        }

        let id = UUID()
        let kind: Kind
        let originalData: Data
        let previewImage: UIImage
        let fileName: String
        let contentType: String
        let aiPreviewJPEG: Data?

        var isImage: Bool { kind == .image }
    }

    private struct LoadedMediaBatch {
        let media: [LoadedMedia]
        let warning: String?
    }

    private enum MediaImportError: LocalizedError {
        case unsupportedType
        case unreadableMedia
        case noSupportedMedia

        var errorDescription: String? {
            switch self {
            case .unsupportedType:
                return "Only photos and videos are supported."
            case .unreadableMedia:
                return "The selected media could not be read."
            case .noSupportedMedia:
                return "No supported photos or videos were found."
            }
        }
    }

    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var mediaItems: [LoadedMedia] = []
    @Published var hintText: String = ""
    @Published var status: String = ""
    @Published var issueURL: URL?
    @Published var isSubmitting = false
    @Published var isLoadingMedia = false
    @Published var enableMarkup = false
    @Published var selectedShape: AnnotationShape = .circle
    @Published var selectedColor: AnnotationColor = .red

    @Published private(set) var marksByMediaID: [UUID: [AnnotationMark]] = [:]

    func refreshSelectedMedia() async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let batch = try await loadMedia(from: selectedItems)
            applyLoadedMedia(batch.media)
            issueURL = nil
            status = batch.warning ?? ""
        } catch {
            mediaItems = []
            marksByMediaID = [:]
            status = "Failed to load media: \(error.localizedDescription)"
        }
    }

    func importSharedMediaIfAvailable() async {
        do {
            let sharedFileURLs = try SharedMediaInbox.takePendingFiles()
            let sharedNotice = SharedMediaInbox.consumePendingImportNotice()
            guard !sharedFileURLs.isEmpty || sharedNotice != nil else { return }

            guard !sharedFileURLs.isEmpty else {
                if let sharedNotice {
                    status = sharedNotice
                }
                return
            }

            isLoadingMedia = true
            defer { isLoadingMedia = false }

            let batch = try loadMedia(from: sharedFileURLs)
            selectedItems = []
            applyLoadedMedia(batch.media)
            issueURL = nil
            status = combinedNotice(sharedNotice, batch.warning) ?? ""
        } catch {
            status = "Failed to import shared media: \(error.localizedDescription)"
        }
    }

    func addMark(mediaID: UUID, normalizedPoint: CGPoint) {
        guard let _ = marksByMediaID[mediaID] else { return }
        let clamped = clampedPoint(normalizedPoint)
        marksByMediaID[mediaID, default: []].append(
            AnnotationMark(points: [clamped], shape: selectedShape, color: selectedColor)
        )
    }

    func addFreehandPoint(mediaID: UUID, normalizedPoint: CGPoint, beginStroke: Bool) {
        guard marksByMediaID[mediaID] != nil else { return }
        let clamped = clampedPoint(normalizedPoint)

        if beginStroke || marksByMediaID[mediaID]?.isEmpty == true {
            marksByMediaID[mediaID, default: []].append(
                AnnotationMark(points: [clamped], shape: .freehand, color: selectedColor)
            )
            return
        }

        guard var marks = marksByMediaID[mediaID], var last = marks.last else { return }
        guard last.shape == .freehand else {
            marks.append(AnnotationMark(points: [clamped], shape: .freehand, color: selectedColor))
            marksByMediaID[mediaID] = marks
            return
        }
        if let previous = last.points.last {
            let dx = clamped.x - previous.x
            let dy = clamped.y - previous.y
            if (dx * dx + dy * dy) < 0.000005 {
                return
            }
        }
        last.points.append(clamped)
        marks[marks.count - 1] = last
        marksByMediaID[mediaID] = marks
    }

    func undoMark(mediaID: UUID) {
        guard var marks = marksByMediaID[mediaID], !marks.isEmpty else { return }
        marks.removeLast()
        marksByMediaID[mediaID] = marks
    }

    func clearMarks(mediaID: UUID) {
        guard marksByMediaID[mediaID] != nil else { return }
        marksByMediaID[mediaID] = []
    }

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
            if mediaItems.isEmpty, !selectedItems.isEmpty {
                await refreshSelectedMedia()
            }
            let attachments = try loadAttachmentsFromPreparedMedia()
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

    private func loadMedia(from items: [PhotosPickerItem]) async throws -> LoadedMediaBatch {
        guard !items.isEmpty else {
            return LoadedMediaBatch(media: [], warning: nil)
        }

        var result: [LoadedMedia] = []
        var failures = 0
        var lastError: Error?

        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw MediaImportError.unreadableMedia
                }

                guard let contentType = preferredContentType(for: item.supportedContentTypes) else {
                    throw MediaImportError.unsupportedType
                }

                result.append(
                    try makeLoadedMedia(
                        data: data,
                        contentType: contentType,
                        suggestedFileName: nil,
                        index: index
                    )
                )
            } catch {
                failures += 1
                lastError = error
            }
        }

        return try finalizeLoadedMediaBatch(
            result,
            failures: failures,
            lastError: lastError
        )
    }

    private func loadMedia(from fileURLs: [URL]) throws -> LoadedMediaBatch {
        guard !fileURLs.isEmpty else {
            return LoadedMediaBatch(media: [], warning: nil)
        }

        var result: [LoadedMedia] = []
        var failures = 0
        var lastError: Error?

        for (index, fileURL) in fileURLs.enumerated() {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                guard let contentType = contentType(for: fileURL) else {
                    throw MediaImportError.unsupportedType
                }

                result.append(
                    try makeLoadedMedia(
                        data: data,
                        contentType: contentType,
                        suggestedFileName: fileURL.lastPathComponent,
                        index: index
                    )
                )
            } catch {
                failures += 1
                lastError = error
            }
        }

        return try finalizeLoadedMediaBatch(
            result,
            failures: failures,
            lastError: lastError
        )
    }

    private func loadAttachmentsFromPreparedMedia() throws -> [Attachment] {
        var attachments: [Attachment] = []
        for media in mediaItems {
            if media.isImage {
                let marks = marksByMediaID[media.id] ?? []
                if enableMarkup, !marks.isEmpty {
                    let annotated = try annotatedJPEG(for: media, marks: marks)
                    attachments.append(
                        Attachment(
                            data: annotated,
                            fileName: media.fileName,
                            contentType: media.contentType,
                            aiPreviewJPEG: annotated
                        )
                    )
                } else {
                    attachments.append(
                        Attachment(
                            data: media.originalData,
                            fileName: media.fileName,
                            contentType: media.contentType,
                            aiPreviewJPEG: media.aiPreviewJPEG
                        )
                    )
                }
            } else {
                attachments.append(
                    Attachment(
                        data: media.originalData,
                        fileName: media.fileName,
                        contentType: media.contentType,
                        aiPreviewJPEG: media.aiPreviewJPEG
                    )
                )
            }
        }
        return attachments
    }

    private func annotatedJPEG(for media: LoadedMedia, marks: [AnnotationMark]) throws -> Data {
        let size = media.previewImage.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            media.previewImage.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setLineWidth(max(4, min(size.width, size.height) * 0.008))
            cg.setLineJoin(.round)
            cg.setLineCap(.round)

            for mark in marks {
                let points = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                guard let point = points.first else { continue }
                let shapeSize = max(36, min(size.width, size.height) * 0.16)
                let stroke = mark.color.uiColor
                cg.setStrokeColor(stroke.cgColor)
                cg.setFillColor(stroke.withAlphaComponent(0.18).cgColor)

                switch mark.shape {
                case .freehand:
                    guard points.count > 1 else { continue }
                    cg.beginPath()
                    cg.move(to: points[0])
                    for p in points.dropFirst() {
                        cg.addLine(to: p)
                    }
                    cg.strokePath()
                case .circle:
                    let rect = CGRect(x: point.x - shapeSize / 2, y: point.y - shapeSize / 2, width: shapeSize, height: shapeSize)
                    cg.strokeEllipse(in: rect)
                case .rectangle:
                    let rect = CGRect(x: point.x - shapeSize / 2, y: point.y - shapeSize / 2, width: shapeSize, height: shapeSize)
                    cg.stroke(rect)
                case .arrow:
                    let start = CGPoint(x: point.x - shapeSize * 0.45, y: point.y + shapeSize * 0.45)
                    let end = CGPoint(x: point.x, y: point.y)
                    cg.beginPath()
                    cg.move(to: start)
                    cg.addLine(to: end)
                    cg.strokePath()

                    let head = shapeSize * 0.22
                    cg.beginPath()
                    cg.move(to: end)
                    cg.addLine(to: CGPoint(x: end.x - head, y: end.y + head * 0.65))
                    cg.move(to: end)
                    cg.addLine(to: CGPoint(x: end.x - head * 0.25, y: end.y + head))
                    cg.strokePath()
                }
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "MainViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode annotated image"])
        }
        return data
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func applyLoadedMedia(_ media: [LoadedMedia]) {
        mediaItems = media

        var nextMarks: [UUID: [AnnotationMark]] = [:]
        for item in media where item.isImage {
            nextMarks[item.id] = []
        }
        marksByMediaID = nextMarks
    }

    private func finalizeLoadedMediaBatch(
        _ media: [LoadedMedia],
        failures: Int,
        lastError: Error?
    ) throws -> LoadedMediaBatch {
        if media.isEmpty {
            if failures > 0 {
                throw lastError ?? MediaImportError.noSupportedMedia
            }
            return LoadedMediaBatch(media: [], warning: nil)
        }

        let warning = failures > 0 ? "Some selected items could not be imported." : nil
        return LoadedMediaBatch(media: media, warning: warning)
    }

    private func preferredContentType(for contentTypes: [UTType]) -> UTType? {
        contentTypes.first {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .audiovisualContent)
        } ?? contentTypes.first {
            $0.conforms(to: .image)
        }
    }

    private func contentType(for fileURL: URL) -> UTType? {
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let resourceType = resourceValues.contentType {
            return resourceType
        }

        if !fileURL.pathExtension.isEmpty {
            return UTType(filenameExtension: fileURL.pathExtension)
        }

        return nil
    }

    private func makeLoadedMedia(
        data: Data,
        contentType: UTType,
        suggestedFileName: String?,
        index: Int
    ) throws -> LoadedMedia {
        if contentType.conforms(to: .movie)
            || contentType.conforms(to: .video)
            || contentType.conforms(to: .audiovisualContent) {
            let previewJPEG = VideoThumbnail.jpegPreview(from: data)
            let previewImage = previewJPEG.flatMap(UIImage.init(data:)) ?? UIImage()
            return LoadedMedia(
                kind: .video,
                originalData: data,
                previewImage: previewImage,
                fileName: makeFileName(
                    suggestedFileName: suggestedFileName,
                    defaultStem: "attachment-\(index + 1)",
                    defaultExtension: contentType.preferredFilenameExtension ?? "mov"
                ),
                contentType: contentType.preferredMIMEType ?? "video/quicktime",
                aiPreviewJPEG: previewJPEG
            )
        }

        guard contentType.conforms(to: .image) else {
            throw MediaImportError.unsupportedType
        }

        let jpeg = ImageCompression.compressedJPEG(data)
        guard let image = UIImage(data: jpeg) else {
            throw MediaImportError.unreadableMedia
        }

        return LoadedMedia(
            kind: .image,
            originalData: jpeg,
            previewImage: image,
            fileName: makeFileName(
                suggestedFileName: suggestedFileName,
                defaultStem: "attachment-\(index + 1)",
                defaultExtension: "jpg"
            ),
            contentType: "image/jpeg",
            aiPreviewJPEG: jpeg
        )
    }

    private func makeFileName(
        suggestedFileName: String?,
        defaultStem: String,
        defaultExtension: String
    ) -> String {
        guard let suggestedFileName, !suggestedFileName.isEmpty else {
            return "\(defaultStem).\(defaultExtension)"
        }

        let baseURL = URL(fileURLWithPath: suggestedFileName)
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension.isEmpty ? defaultExtension : baseURL.pathExtension
        return "\(stem.isEmpty ? defaultStem : stem).\(ext)"
    }

    private func combinedNotice(_ first: String?, _ second: String?) -> String? {
        let notices = [first, second]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !notices.isEmpty else { return nil }
        return Array(NSOrderedSet(array: notices)).compactMap { $0 as? String }.joined(separator: "\n")
    }
}
