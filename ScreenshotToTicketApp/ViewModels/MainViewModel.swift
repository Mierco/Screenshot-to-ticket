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

    private func loadMedia(from items: [PhotosPickerItem]) async throws -> [LoadedMedia] {
        var result: [LoadedMedia] = []
        for (index, item) in items.enumerated() {
            if let data = try await item.loadTransferable(type: Data.self) {
                let isVideo = item.supportedContentTypes.contains {
                    $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .audiovisualContent)
                }
                if isVideo {
                    let preview = VideoThumbnail.jpegPreview(from: data).flatMap(UIImage.init(data:)) ?? UIImage()
                    result.append(
                        LoadedMedia(
                            kind: .video,
                            originalData: data,
                            previewImage: preview,
                            fileName: "attachment-\(index + 1).mp4",
                            contentType: "video/mp4",
                            aiPreviewJPEG: VideoThumbnail.jpegPreview(from: data)
                        )
                    )
                } else {
                    let jpeg = ImageCompression.compressedJPEG(data)
                    guard let image = UIImage(data: jpeg) else { continue }
                    result.append(
                        LoadedMedia(
                            kind: .image,
                            originalData: jpeg,
                            previewImage: image,
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
}
