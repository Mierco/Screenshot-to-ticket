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

                    if vm.isLoadingMedia {
                        ProgressView("Loading selected media...")
                    } else {
                        Text("Selected: \(vm.mediaItems.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                if !vm.mediaItems.isEmpty {
                    Section("Highlight (Optional)") {
                        Toggle("Enable markups on screenshots", isOn: $vm.enableMarkup)

                        if vm.enableMarkup {
                            Picker("Shape", selection: $vm.selectedShape) {
                                ForEach(MainViewModel.AnnotationShape.allCases) { shape in
                                    Text(shape.rawValue).tag(shape)
                                }
                            }
                            .pickerStyle(.segmented)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(MainViewModel.AnnotationColor.allCases) { color in
                                        Button {
                                            vm.selectedColor = color
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(color.swatch)
                                                    .frame(width: 26, height: 26)
                                                if vm.selectedColor == color {
                                                    Circle()
                                                        .stroke(.primary, lineWidth: 2)
                                                        .frame(width: 34, height: 34)
                                                }
                                            }
                                            .frame(width: 36, height: 36)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.vertical, 2)
                                        .accessibilityLabel(color.rawValue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            Text(vm.selectedShape == .freehand ? "Drag on each screenshot to draw a highlight." : "Tap on each screenshot to place a marker.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            ForEach(vm.mediaItems) { media in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(media.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    AnnotationCanvasView(
                                        image: media.previewImage,
                                        marks: vm.marksByMediaID[media.id] ?? [],
                                        interactive: media.isImage,
                                        selectedShape: vm.selectedShape
                                    ) { point in
                                        vm.addMark(mediaID: media.id, normalizedPoint: point)
                                    } onFreehandPoint: { point, isStart in
                                        vm.addFreehandPoint(mediaID: media.id, normalizedPoint: point, beginStroke: isStart)
                                    }
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                    }

                                    if media.isImage {
                                        HStack {
                                            Button("Undo") { vm.undoMark(mediaID: media.id) }
                                            Button("Clear") { vm.clearMarks(mediaID: media.id) }
                                        }
                                        .font(.footnote)
                                    } else {
                                        Text("Markup is available for images only.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
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
        .onChange(of: vm.selectedItems) { _ in
            Task { await vm.refreshSelectedMedia() }
        }
    }
}

private struct AnnotationCanvasView: View {
    let image: UIImage
    let marks: [MainViewModel.AnnotationMark]
    let interactive: Bool
    let selectedShape: MainViewModel.AnnotationShape
    let onTap: (CGPoint) -> Void
    let onFreehandPoint: (CGPoint, Bool) -> Void

    @State private var startedStroke = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let drawRect = aspectFitRect(imageSize: image.size, in: CGRect(origin: .zero, size: size))

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))

                ForEach(marks) { mark in
                    if mark.shape == .freehand {
                        freehandPath(mark.points, in: drawRect)
                            .stroke(mark.color.swatch, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    } else if let point = mark.points.first {
                        annotationShape(mark.shape)
                            .stroke(mark.color.swatch, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .frame(width: 42, height: 42)
                            .position(
                                x: drawRect.minX + (point.x * drawRect.width),
                                y: drawRect.minY + (point.y * drawRect.height)
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .modifier(
                AnnotationInteractionModifier(
                    interactive: interactive,
                    selectedShape: selectedShape,
                    drawRect: drawRect,
                    onTap: onTap,
                    onFreehandPoint: onFreehandPoint,
                    startedStroke: $startedStroke
                )
            )
        }
    }

    private func annotationShape(_ shape: MainViewModel.AnnotationShape) -> Path {
        switch shape {
        case .freehand:
            return Path()
        case .circle:
            return Path(ellipseIn: CGRect(x: 0, y: 0, width: 42, height: 42))
        case .rectangle:
            return Path(CGRect(x: 0, y: 0, width: 42, height: 42))
        case .arrow:
            var path = Path()
            path.move(to: CGPoint(x: 4, y: 38))
            path.addLine(to: CGPoint(x: 33, y: 10))
            path.move(to: CGPoint(x: 33, y: 10))
            path.addLine(to: CGPoint(x: 33, y: 23))
            path.move(to: CGPoint(x: 33, y: 10))
            path.addLine(to: CGPoint(x: 20, y: 10))
            return path
        }
    }

    private func freehandPath(_ points: [CGPoint], in drawRect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(
            to: CGPoint(
                x: drawRect.minX + (first.x * drawRect.width),
                y: drawRect.minY + (first.y * drawRect.height)
            )
        )
        for point in points.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: drawRect.minX + (point.x * drawRect.width),
                    y: drawRect.minY + (point.y * drawRect.height)
                )
            )
        }
        return path
    }

    private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let imageAspect = imageSize.width / imageSize.height
        let boundsAspect = bounds.width / bounds.height
        if imageAspect > boundsAspect {
            let width = bounds.width
            let height = width / imageAspect
            let y = bounds.minY + (bounds.height - height) / 2
            return CGRect(x: bounds.minX, y: y, width: width, height: height)
        } else {
            let height = bounds.height
            let width = height * imageAspect
            let x = bounds.minX + (bounds.width - width) / 2
            return CGRect(x: x, y: bounds.minY, width: width, height: height)
        }
    }
}

private struct AnnotationInteractionModifier: ViewModifier {
    let interactive: Bool
    let selectedShape: MainViewModel.AnnotationShape
    let drawRect: CGRect
    let onTap: (CGPoint) -> Void
    let onFreehandPoint: (CGPoint, Bool) -> Void
    @Binding var startedStroke: Bool

    func body(content: Content) -> some View {
        content
            .onTapGesture { location in
                guard interactive, selectedShape != .freehand else { return }
                guard let normalized = normalize(location) else { return }
                onTap(normalized)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactive, selectedShape == .freehand else { return }
                        guard let normalized = normalize(value.location) else { return }
                        onFreehandPoint(normalized, !startedStroke)
                        startedStroke = true
                    }
                    .onEnded { _ in
                        startedStroke = false
                    }
            )
    }

    private func normalize(_ point: CGPoint) -> CGPoint? {
        guard drawRect.contains(point), drawRect.width > 0, drawRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - drawRect.minX) / drawRect.width,
            y: (point.y - drawRect.minY) / drawRect.height
        )
    }
}
