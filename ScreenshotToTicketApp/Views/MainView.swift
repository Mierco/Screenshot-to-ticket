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
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

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
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Opacity")
                                    Spacer()
                                    Text("\(Int((vm.markupOpacity * 100).rounded()))%")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)

                                Slider(value: $vm.markupOpacity, in: 0.1...1.0, step: 0.05)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Canvas size")
                                    Spacer()
                                    Text("\(Int((vm.markupCanvasScale * 100).rounded()))%")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)

                                Slider(value: $vm.markupCanvasScale, in: 0.8...1.6, step: 0.05)
                            }

                            Text("Drag on each screenshot to draw a freehand highlight. Increase canvas size for more detail; wider canvases can be panned horizontally.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            ForEach(vm.mediaItems) { media in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(media.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ResizableAnnotationCanvasView(
                                        image: media.previewImage,
                                        marks: vm.marksByMediaID[media.id] ?? [],
                                        interactive: media.isImage,
                                        opacity: vm.markupOpacity,
                                        canvasScale: vm.markupCanvasScale
                                    ) { point, isStart in
                                        vm.addFreehandPoint(mediaID: media.id, normalizedPoint: point, beginStroke: isStart)
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
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Screenshot to Jira")
                            .font(.headline)

                        Text(AppBuildInfo.badgeText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Screenshot to Jira, \(AppBuildInfo.badgeText)")
                }

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

private struct ResizableAnnotationCanvasView: View {
    let image: UIImage
    let marks: [MainViewModel.AnnotationMark]
    let interactive: Bool
    let opacity: Double
    let canvasScale: Double
    let onFreehandPoint: (CGPoint, Bool) -> Void

    @State private var availableWidth = max(280, UIScreen.main.bounds.width - 32)

    var body: some View {
        let canvasSize = calculatedCanvasSize(for: image, availableWidth: availableWidth, scale: canvasScale)

        ScrollView(.horizontal, showsIndicators: canvasSize.width > availableWidth + 1) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                AnnotationCanvasView(
                    image: image,
                    marks: marks,
                    interactive: interactive,
                    opacity: opacity,
                    onFreehandPoint: onFreehandPoint
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                Spacer(minLength: 0)
            }
            .frame(minWidth: availableWidth)
        }
        .background(WidthObserver(width: $availableWidth))
        .frame(height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private func calculatedCanvasSize(for image: UIImage, availableWidth: CGFloat, scale: Double) -> CGSize {
        let natural = naturalPointSize(for: image)
        guard natural.width > 0, natural.height > 0 else {
            return CGSize(width: max(availableWidth, 280), height: 360)
        }

        let baseWidth = max(availableWidth, 280)
        let aspect = natural.width / natural.height
        let maxWidth = baseWidth * 2.4
        let minHeight: CGFloat = 280
        let maxHeight: CGFloat = 900

        var width = min(baseWidth * CGFloat(scale), maxWidth)
        var height = width / aspect

        if height < minHeight {
            width = min(max(width, minHeight * aspect), maxWidth)
            height = width / aspect
        }

        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }

        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private func naturalPointSize(for image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else { return image.size }
        let screenScale = max(UIScreen.main.scale, 1)
        return CGSize(
            width: CGFloat(cgImage.width) / screenScale,
            height: CGFloat(cgImage.height) / screenScale
        )
    }
}

private struct WidthObserver: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { newWidth in
                    updateWidth(newWidth)
                }
        }
    }

    private func updateWidth(_ newWidth: CGFloat) {
        guard newWidth > 0, abs(width - newWidth) > 0.5 else { return }
        width = newWidth
    }
}

private struct AnnotationCanvasView: View {
    let image: UIImage
    let marks: [MainViewModel.AnnotationMark]
    let interactive: Bool
    let opacity: Double
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
                    freehandPath(mark.points, in: drawRect)
                        .stroke(
                            mark.color.swatch.opacity(opacity),
                            style: StrokeStyle(lineWidth: lineWidth(in: drawRect), lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .contentShape(Rectangle())
            .modifier(
                AnnotationInteractionModifier(
                    interactive: interactive,
                    drawRect: drawRect,
                    onFreehandPoint: onFreehandPoint,
                    startedStroke: $startedStroke
                )
            )
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

    private func lineWidth(in drawRect: CGRect) -> CGFloat {
        max(3, min(drawRect.width, drawRect.height) * 0.008)
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
    let drawRect: CGRect
    let onFreehandPoint: (CGPoint, Bool) -> Void
    @Binding var startedStroke: Bool

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactive else { return }
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
