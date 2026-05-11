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
                            HStack(spacing: 12) {
                                Button {
                                    vm.isMarkupDrawingMode.toggle()
                                } label: {
                                    Label("Draw", systemImage: "pencil")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(vm.isMarkupDrawingMode ? .accentColor : .secondary)

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

                            Text("Draw colored circles around specific areas that you want to report")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            ForEach(vm.mediaItems) { media in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(media.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ZoomableAnnotationCanvasView(
                                        image: media.previewImage,
                                        marks: vm.marksByMediaID[media.id] ?? [],
                                        interactive: media.isImage && vm.isMarkupDrawingMode,
                                        opacity: vm.markupOpacity
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
        .onChange(of: vm.enableMarkup) { enabled in
            if !enabled {
                vm.isMarkupDrawingMode = false
            }
        }
    }
}

private struct ZoomableAnnotationCanvasView: View {
    let image: UIImage
    let marks: [MainViewModel.AnnotationMark]
    let interactive: Bool
    let opacity: Double
    let onFreehandPoint: (CGPoint, Bool) -> Void

    @State private var availableWidth = max(280, UIScreen.main.bounds.width - 32)

    var body: some View {
        let canvasSize = calculatedCanvasSize(for: image, availableWidth: availableWidth)

        UIKitAnnotationCanvasView(
            image: image,
            marks: marks,
            interactive: interactive,
            opacity: opacity,
            canvasSize: canvasSize,
            onFreehandPoint: onFreehandPoint
        )
        .background(WidthObserver(width: $availableWidth))
        .frame(height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private func calculatedCanvasSize(for image: UIImage, availableWidth: CGFloat) -> CGSize {
        let natural = naturalPointSize(for: image)
        guard natural.width > 0, natural.height > 0 else {
            return CGSize(width: max(availableWidth, 280), height: 360)
        }

        let baseWidth = max(availableWidth, 280)
        let aspect = natural.width / natural.height
        let maxWidth = baseWidth * 2.4
        let minHeight: CGFloat = 280
        let maxHeight: CGFloat = 760

        var width = min(baseWidth, maxWidth)
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

private struct UIKitAnnotationCanvasView: UIViewRepresentable {
    let image: UIImage
    let marks: [MainViewModel.AnnotationMark]
    let interactive: Bool
    let opacity: Double
    let canvasSize: CGSize
    let onFreehandPoint: (CGPoint, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .secondarySystemBackground
        scrollView.delegate = context.coordinator
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(doubleTap)

        let drawingView = AnnotationDrawingUIView(frame: CGRect(origin: .zero, size: canvasSize))
        drawingView.backgroundColor = .secondarySystemBackground
        context.coordinator.drawingView = drawingView
        scrollView.addSubview(drawingView)
        scrollView.contentSize = canvasSize

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let drawingView = context.coordinator.drawingView else { return }

        let sizeChanged = drawingView.bounds.size != canvasSize
        drawingView.image = image
        drawingView.marks = marks
        drawingView.interactive = interactive
        drawingView.isUserInteractionEnabled = interactive
        drawingView.opacity = opacity
        drawingView.onFreehandPoint = onFreehandPoint
        drawingView.setNeedsDisplay()

        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        if sizeChanged {
            scrollView.setZoomScale(1, animated: false)
            drawingView.frame = CGRect(origin: .zero, size: canvasSize)
            scrollView.contentSize = canvasSize
        }
        context.coordinator.centerContent(in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var drawingView: AnnotationDrawingUIView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            drawingView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard
                recognizer.state == .ended,
                let scrollView = recognizer.view as? UIScrollView,
                let drawingView = drawingView
            else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale * 2.5, 1.5))
            let tapPoint = recognizer.location(in: drawingView)
            let zoomRect = zoomRect(centeredAt: tapPoint, scale: targetScale, in: scrollView, contentBounds: drawingView.bounds)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        func centerContent(in scrollView: UIScrollView) {
            guard let drawingView = drawingView else { return }

            let boundsSize = scrollView.bounds.size
            let contentSize = drawingView.frame.size
            let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        private func zoomRect(centeredAt center: CGPoint, scale: CGFloat, in scrollView: UIScrollView, contentBounds: CGRect) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let maxX = max(contentBounds.minX, contentBounds.maxX - size.width)
            let maxY = max(contentBounds.minY, contentBounds.maxY - size.height)
            let origin = CGPoint(
                x: min(max(center.x - size.width / 2, contentBounds.minX), maxX),
                y: min(max(center.y - size.height / 2, contentBounds.minY), maxY)
            )
            return CGRect(origin: origin, size: size)
        }
    }
}

private final class AnnotationDrawingUIView: UIView {
    var image = UIImage()
    var marks: [MainViewModel.AnnotationMark] = []
    var interactive = false
    var opacity = 0.75
    var onFreehandPoint: ((CGPoint, Bool) -> Void)?

    private var drawingStroke = false
    private var pendingStartPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        isOpaque = true
    }

    override func draw(_ rect: CGRect) {
        UIColor.secondarySystemBackground.setFill()
        UIRectFill(bounds)

        let drawRect = aspectFitRect(imageSize: image.size, in: bounds)
        image.draw(in: drawRect)

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineWidth(max(3, min(drawRect.width, drawRect.height) * 0.008))

        for mark in marks {
            let points = mark.points.map {
                CGPoint(
                    x: drawRect.minX + ($0.x * drawRect.width),
                    y: drawRect.minY + ($0.y * drawRect.height)
                )
            }
            guard points.count > 1 else { continue }

            context.setStrokeColor(mark.color.uiColor.withAlphaComponent(CGFloat(opacity)).cgColor)
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard interactive, event?.allTouches?.count == 1, let touch = touches.first else {
            drawingStroke = false
            pendingStartPoint = nil
            return
        }
        drawingStroke = addPoint(from: touch, beginStroke: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard interactive, drawingStroke, event?.allTouches?.count == 1, let touch = touches.first else { return }
        _ = addPoint(from: touch, beginStroke: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if interactive, drawingStroke, pendingStartPoint == nil, let touch = touches.first {
            _ = addPoint(from: touch, beginStroke: false)
        }
        drawingStroke = false
        pendingStartPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        drawingStroke = false
        pendingStartPoint = nil
    }

    private func addPoint(from touch: UITouch, beginStroke: Bool) -> Bool {
        guard let normalized = normalizedPoint(touch.location(in: self)) else { return false }
        if beginStroke {
            pendingStartPoint = normalized
            return true
        }
        if let startPoint = pendingStartPoint {
            onFreehandPoint?(startPoint, true)
            pendingStartPoint = nil
        }
        onFreehandPoint?(normalized, beginStroke)
        return true
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint? {
        let drawRect = aspectFitRect(imageSize: image.size, in: bounds)
        guard drawRect.contains(point), drawRect.width > 0, drawRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - drawRect.minX) / drawRect.width,
            y: (point.y - drawRect.minY) / drawRect.height
        )
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
