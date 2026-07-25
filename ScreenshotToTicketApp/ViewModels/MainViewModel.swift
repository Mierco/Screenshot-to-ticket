import Foundation
import ImageIO
import Photos
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
        let metadata: ScreenshotMetadata?
    }

    struct ScreenshotMetadata {
        var capturedAt: Date?
        var device: String?
        var osVersion: String?

        var hasReadableValues: Bool {
            capturedAt != nil || device != nil || osVersion != nil
        }
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
        let metadata: ScreenshotMetadata?

        var isImage: Bool { kind == .image }
    }

    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var mediaItems: [LoadedMedia] = []
    @Published var hintText: String = ""
    @Published var draftSummary: String = ""
    @Published var draftDescription: String = ""
    @Published var status: String = ""
    @Published var issueURL: URL?
    @Published var isSubmitting = false
    @Published private(set) var isPreparingDraft = false
    @Published var isLoadingMedia = false
    @Published var enableMarkup = false
    @Published var isMarkupDrawingMode = false
    @Published var selectedColor: AnnotationColor = .red
    let markupOpacity = 0.75

    @Published private(set) var hasDraft = false
    @Published private(set) var marksByMediaID: [UUID: [AnnotationMark]] = [:]

    func refreshSelectedMedia() async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            mediaItems = try await loadMedia(from: Array(selectedItems.prefix(3)))
            var nextMarks: [UUID: [AnnotationMark]] = [:]
            for media in mediaItems where media.isImage {
                nextMarks[media.id] = []
            }
            marksByMediaID = nextMarks
        } catch {
            mediaItems = []
            marksByMediaID = [:]
            status = "Failed to load media: \(error.localizedDescription)"
        }
    }

    func addFreehandPoint(mediaID: UUID, normalizedPoint: CGPoint, beginStroke: Bool) {
        guard marksByMediaID[mediaID] != nil else { return }
        let clamped = clampedPoint(normalizedPoint)

        if beginStroke || marksByMediaID[mediaID]?.isEmpty == true {
            marksByMediaID[mediaID, default: []].append(
                AnnotationMark(points: [clamped], color: selectedColor)
            )
            return
        }

        guard var marks = marksByMediaID[mediaID], var last = marks.last else { return }
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

    func discardDraft() {
        draftSummary = ""
        draftDescription = ""
        hasDraft = false
        issueURL = nil
        status = ""
    }

    func prepareDraft(settings: SettingsStore) async {
        issueURL = nil
        guard settings.isConfigured else {
            status = "Complete the Jira profile and OpenAI settings."
            return
        }

        isPreparingDraft = true
        isSubmitting = true
        defer {
            isPreparingDraft = false
            isSubmitting = false
        }

        do {
            let attachments = try await preparedAttachments()
            let aiImages = attachments.compactMap(\.aiPreviewJPEG)
            let draft = try await draftTicket(
                images: aiImages,
                settings: settings
            )
            let metadataText = Self.metadataDescription(from: attachments)
            let notes = hintText.isEmpty ? "" : "\n\nReporter notes:\n\(hintText)"
            draftSummary = draft.summary
            draftDescription = draft.description + metadataText + notes
            hasDraft = true
            status = "Ticket draft ready for review."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    func submit(settings: SettingsStore) async {
        issueURL = nil
        guard settings.isConfigured else {
            status = "Complete the Jira profile and OpenAI settings."
            return
        }
        guard hasDraft else {
            status = "Review the ticket draft before creating it."
            return
        }

        let summary = draftSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !description.isEmpty else {
            status = "Ticket summary and description cannot be empty."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let attachments = try await preparedAttachments()
            try await createTicket(
                summary: summary,
                description: description,
                attachments: attachments,
                settings: settings
            )
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func preparedAttachments() async throws -> [Attachment] {
        status = "Loading media..."
        if mediaItems.isEmpty, !selectedItems.isEmpty {
            await refreshSelectedMedia()
        }
        let attachments = try loadAttachmentsFromPreparedMedia()
        guard attachments.contains(where: { $0.aiPreviewJPEG != nil }) else {
            throw NSError(
                domain: "MainViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select at least one image or video."]
            )
        }
        return attachments
    }

    private func draftTicket(
        images: [Data],
        settings: SettingsStore
    ) async throws -> TicketDraft {
        status = "OpenAI is drafting ticket text..."
        return try await OpenAIClient(
            apiKey: settings.openAIKey,
            model: settings.model,
            reasoningEffort: settings.reasoningEffort,
            ticketPrompt: settings.effectiveTicketPrompt
        ).draftTicket(from: images, userHint: hintText)
    }

    private func createTicket(
        summary: String,
        description: String,
        attachments: [Attachment],
        settings: SettingsStore
    ) async throws {
        guard let jiraProfile = settings.activeJiraProfile else {
            throw NSError(
                domain: "MainViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Select a Jira profile in Settings."]
            )
        }
        let defaultFields = try settings.defaultFields(for: jiraProfile)

        let jira = try await settings.jiraClient(
            workspaceURL: jiraProfile.workspaceURL,
            projectKey: jiraProfile.projectKey
        )

        status = "Resolving fix version..."
        let fixVersion = try await jira.fetchBiggestUnreleasedVersion()
        let resolvedDefaultFields = try Self.resolvedDefaultFields(
            defaultFields,
            latestUnreleasedVersion: fixVersion
        )

        status = "Creating Jira issue..."
        let issue = try await jira.createIssue(
            summary: summary,
            description: jira.adfDescription(from: description),
            fixVersionId: fixVersion?.id,
            defaultFields: resolvedDefaultFields
        )

        status = "Uploading media..."
        var uploadedAttachments: [JiraAttachmentMetadata] = []
        for attachment in attachments {
            let uploaded = try await jira.attachFile(
                issueKey: issue.key,
                data: attachment.data,
                fileName: attachment.fileName,
                contentType: attachment.contentType
            )
            uploadedAttachments.append(uploaded)
        }

        status = "Embedding media in description..."
        do {
            try await jira.updateIssueDescription(
                issueKey: issue.key,
                description: jira.adfDescription(from: description, attachments: uploadedAttachments)
            )
        } catch {
            try await jira.updateIssueDescription(
                issueKey: issue.key,
                description: jira.adfDescriptionWithAttachmentLinks(from: description, attachments: uploadedAttachments)
            )
        }

        let base = jiraProfile.workspaceURL.hasSuffix("/") ? String(jiraProfile.workspaceURL.dropLast()) : jiraProfile.workspaceURL
        issueURL = URL(string: "\(base)/browse/\(issue.key)")
        status = "Done: \(issue.key)"
    }

    private func loadMedia(from items: [PhotosPickerItem]) async throws -> [LoadedMedia] {
        var result: [LoadedMedia] = []
        for (index, item) in items.enumerated() {
            if let data = try await item.loadTransferable(type: Data.self) {
                let asset = Self.photoAsset(for: item)
                let isVideo = item.supportedContentTypes.contains {
                    $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .audiovisualContent)
                }
                if isVideo {
                    let previewJPEG = VideoThumbnail.jpegPreview(from: data)
                    let videoType = Self.preferredContentType(
                        from: item,
                        conformingTo: [.movie, .video, .audiovisualContent]
                    )
                    let preview = previewJPEG.flatMap(UIImage.init(data:)) ?? UIImage()
                    result.append(
                        LoadedMedia(
                            kind: .video,
                            originalData: data,
                            previewImage: preview,
                            fileName: "attachment-\(index + 1).\(videoType?.preferredFilenameExtension ?? "mp4")",
                            contentType: videoType?.preferredMIMEType ?? "video/mp4",
                            aiPreviewJPEG: previewJPEG,
                            metadata: Self.mediaMetadata(asset: asset)
                        )
                    )
                } else {
                    let metadata = Self.mediaMetadata(fromImageData: data, asset: asset)
                    let jpeg = ImageCompression.compressedJPEG(data)
                    guard let image = UIImage(data: jpeg) else { continue }
                    result.append(
                        LoadedMedia(
                            kind: .image,
                            originalData: jpeg,
                            previewImage: image,
                            fileName: "attachment-\(index + 1).jpg",
                            contentType: "image/jpeg",
                            aiPreviewJPEG: jpeg,
                            metadata: metadata
                        )
                    )
                }
            }
        }
        return result
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
                            aiPreviewJPEG: annotated,
                            metadata: media.metadata
                        )
                    )
                } else {
                    attachments.append(
                        Attachment(
                            data: media.originalData,
                            fileName: media.fileName,
                            contentType: media.contentType,
                            aiPreviewJPEG: media.aiPreviewJPEG,
                            metadata: media.metadata
                        )
                    )
                }
            } else {
                attachments.append(
                    Attachment(
                        data: media.originalData,
                        fileName: media.fileName,
                        contentType: media.contentType,
                        aiPreviewJPEG: media.aiPreviewJPEG,
                        metadata: media.metadata
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
                let stroke = mark.color.uiColor.withAlphaComponent(CGFloat(markupOpacity))
                cg.setStrokeColor(stroke.cgColor)

                guard points.count > 1 else { continue }
                cg.beginPath()
                cg.move(to: points[0])
                for p in points.dropFirst() {
                    cg.addLine(to: p)
                }
                cg.strokePath()
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "MainViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode annotated image"])
        }
        return data
    }

    private static func resolvedDefaultFields(
        _ fields: [String: Any],
        latestUnreleasedVersion: JiraVersion?
    ) throws -> [String: Any] {
        try resolveDynamicDefaultFieldValue(
            fields,
            latestUnreleasedVersion: latestUnreleasedVersion
        ) as? [String: Any] ?? fields
    }

    private static func resolveDynamicDefaultFieldValue(
        _ value: Any,
        latestUnreleasedVersion: JiraVersion?
    ) throws -> Any {
        if let object = value as? [String: Any] {
            if object["id"] as? String == JiraDynamicFieldValue.latestUnreleasedVersionID {
                guard let latestUnreleasedVersion else {
                    throw NSError(
                        domain: "MainViewModel",
                        code: 8,
                        userInfo: [NSLocalizedDescriptionKey: "A profile uses \(JiraDynamicFieldValue.latestUnreleasedVersionLabel), but this project has no unreleased versions."]
                    )
                }
                return ["id": latestUnreleasedVersion.id]
            }

            var resolved: [String: Any] = [:]
            for (key, value) in object {
                resolved[key] = try resolveDynamicDefaultFieldValue(
                    value,
                    latestUnreleasedVersion: latestUnreleasedVersion
                )
            }
            return resolved
        }

        if let array = value as? [Any] {
            return try array.map {
                try resolveDynamicDefaultFieldValue(
                    $0,
                    latestUnreleasedVersion: latestUnreleasedVersion
                )
            }
        }

        return value
    }

    private static func photoAsset(for item: PhotosPickerItem) -> PHAsset? {
        guard let itemIdentifier = item.itemIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil).firstObject
    }

    private static func preferredContentType(from item: PhotosPickerItem, conformingTo targetTypes: [UTType]) -> UTType? {
        item.supportedContentTypes.first { contentType in
            targetTypes.contains { contentType.conforms(to: $0) }
        }
    }

    private static func mediaMetadata(asset: PHAsset?) -> ScreenshotMetadata? {
        let metadata = ScreenshotMetadata(capturedAt: asset?.creationDate)
        return metadata.hasReadableValues ? metadata : nil
    }

    private static func mediaMetadata(fromImageData data: Data, asset: PHAsset?) -> ScreenshotMetadata? {
        var metadata = mediaMetadata(asset: asset) ?? ScreenshotMetadata()
        guard let properties = imageProperties(from: data) else {
            return metadata.hasReadableValues ? metadata : nil
        }

        metadata.capturedAt = metadata.capturedAt ?? capturedAt(from: properties)
        metadata.device = deviceName(from: properties)
        metadata.osVersion = osVersion(from: properties)

        return metadata.hasReadableValues ? metadata : nil
    }

    private static func imageProperties(from data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        return properties
    }

    private static func capturedAt(from properties: [String: Any]) -> Date? {
        let exif = dictionary(properties, for: kCGImagePropertyExifDictionary)
        let png = dictionary(properties, for: kCGImagePropertyPNGDictionary)
        let tiff = dictionary(properties, for: kCGImagePropertyTIFFDictionary)

        if let date = dateValue(
            exif?[kCGImagePropertyExifDateTimeOriginal as String],
            offset: stringValue(exif?[kCGImagePropertyExifOffsetTimeOriginal as String])
        ) {
            return date
        }

        if let date = dateValue(png?[kCGImagePropertyPNGCreationTime as String], offset: nil) {
            return date
        }

        return dateValue(tiff?[kCGImagePropertyTIFFDateTime as String], offset: nil)
    }

    private static func deviceName(from properties: [String: Any]) -> String? {
        guard let tiff = dictionary(properties, for: kCGImagePropertyTIFFDictionary) else { return nil }
        let make = stringValue(tiff[kCGImagePropertyTIFFMake as String])
        let model = stringValue(tiff[kCGImagePropertyTIFFModel as String])

        switch (make, model) {
        case let (make?, model?) where model.localizedCaseInsensitiveContains(make):
            return model
        case let (make?, model?):
            return "\(make) \(model)"
        case let (_, model?):
            return model
        default:
            return nil
        }
    }

    private static func osVersion(from properties: [String: Any]) -> String? {
        let tiff = dictionary(properties, for: kCGImagePropertyTIFFDictionary)
        let png = dictionary(properties, for: kCGImagePropertyPNGDictionary)
        let software = [
            stringValue(tiff?[kCGImagePropertyTIFFSoftware as String]),
            stringValue(png?[kCGImagePropertyPNGSoftware as String])
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let software else { return nil }
        let lowercased = software.lowercased()
        if lowercased.contains("ios") || lowercased.contains("ipados") {
            return software
        }

        if deviceName(from: properties) != nil,
           software.range(of: #"^\d+(\.\d+){1,2}$"#, options: .regularExpression) != nil {
            return "iOS \(software)"
        }

        return nil
    }

    private static func dictionary(_ properties: [String: Any], for key: CFString) -> [String: Any]? {
        properties[key as String] as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let value = value as? NSString {
            return String(value).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func dateValue(_ value: Any?, offset: String?) -> Date? {
        if let value = value as? Date {
            return value
        }

        guard let string = stringValue(value) else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        let candidates: [(String, String)] = [
            ("yyyy:MM:dd HH:mm:ssXXXXX", offset.map { string + $0 } ?? string),
            ("yyyy:MM:dd HH:mm:ss", string),
            ("yyyy-MM-dd'T'HH:mm:ssXXXXX", string),
            ("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", string),
            ("yyyy-MM-dd HH:mm:ss Z", string)
        ]

        for (format, candidate) in candidates {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: candidate) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: string)
    }

    private static func metadataDescription(from attachments: [Attachment]) -> String {
        let entries = attachments.enumerated().compactMap { index, attachment -> String? in
            guard let metadata = attachment.metadata, metadata.hasReadableValues else { return nil }
            var lines = ["Attachment \(index + 1) (\(attachment.fileName))"]
            if let capturedAt = metadata.capturedAt {
                lines.append("- Date/time: \(displayDateFormatter.string(from: capturedAt))")
            }
            if let device = metadata.device {
                lines.append("- Device: \(device)")
            }
            if let osVersion = metadata.osVersion {
                lines.append("- OS version: \(osVersion)")
            }
            return lines.joined(separator: "\n")
        }

        guard !entries.isEmpty else { return "" }
        return "\n\nScreenshot metadata:\n" + entries.joined(separator: "\n\n")
    }

    private static var displayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
