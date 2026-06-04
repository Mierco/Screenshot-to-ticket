import PhotosUI
import SwiftUI
import UIKit

struct MainView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var vm = MainViewModel()

    private let appAccent = Color(red: 0.57, green: 0.78, blue: 0.00)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        capturePanel

                        if !settings.isConfigured {
                            readinessPanel
                        } else if settings.jiraProfiles.count > 1 {
                            profileSwitcherPanel
                        }

                        instructionsPanel

                        if !vm.mediaItems.isEmpty {
                            markupPanel
                        }

                        if !vm.status.isEmpty {
                            statusPanel
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 112)
                }

                if shouldShowFloatingDrawButton {
                    VStack {
                        Spacer()

                        HStack {
                            Spacer()
                            floatingDrawButton
                                .padding(.trailing, 18)
                                .padding(.bottom, 94)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                submitBar
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("UnicLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshot to Jira")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Capture, annotate, submit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if !AppBuildInfo.badgeText.isEmpty {
                Text(AppBuildInfo.badgeText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.top, 4)
        .accessibilityLabel("Screenshot to Jira")
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media")
                        .font(.headline)
                    Text(mediaSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !vm.mediaItems.isEmpty {
                    PhotosPicker(
                        selection: $vm.selectedItems,
                        maxSelectionCount: 3,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Replace selected media")
                }
            }

            if vm.mediaItems.isEmpty {
                PhotosPicker(
                    selection: $vm.selectedItems,
                    maxSelectionCount: 3,
                    matching: .any(of: [.images, .videos])
                ) {
                    emptyCaptureDropZone
                }
                .buttonStyle(.plain)
            } else {
                selectedMediaStrip
            }
        }
        .panelStyle()
    }

    private var emptyCaptureDropZone: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(appAccent.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(appAccent)
            }

            VStack(spacing: 5) {
                Text("Select screenshots or videos")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Up to 3 attachments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if vm.isLoadingMedia {
                ProgressView("Loading media...")
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 238)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var selectedMediaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(vm.mediaItems.enumerated()), id: \.element.id) { index, media in
                    mediaThumbnail(media, index: index)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func mediaThumbnail(_ media: MainViewModel.LoadedMedia, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: media.previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 116, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

            HStack(spacing: 4) {
                Image(systemName: media.isImage ? "photo" : "video.fill")
                Text("\(index + 1)")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .padding(7)
        }
        .accessibilityLabel("\(media.fileName), attachment \(index + 1)")
    }

    private var readinessPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Readiness", systemImage: settings.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(settings.isConfigured ? appAccent : .orange)

                Spacer()

                Text(settings.isConfigured ? "Ready" : "Setup needed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(settings.isConfigured ? appAccent : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((settings.isConfigured ? appAccent : Color.orange).opacity(0.12), in: Capsule())
            }

            VStack(spacing: 0) {
                readinessRow(
                    title: "Jira profile",
                    value: activeProfileText,
                    isReady: settings.activeJiraProfile != nil
                )

                Divider()
                    .padding(.leading, 32)

                readinessRow(
                    title: "Credentials",
                    value: credentialStatusText,
                    isReady: hasJiraConnection && !settings.openAIKey.isEmpty
                )
            }

            if !settings.jiraProfiles.isEmpty {
                Picker("Jira Profile", selection: activeJiraProfileSelection) {
                    ForEach(settings.jiraProfiles) { profile in
                        Text("\(profile.name) (\(profile.projectKey))")
                            .tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .panelStyle()
    }

    private var profileSwitcherPanel: some View {
        HStack(spacing: 12) {
            Label("Jira profile", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(appAccent)
                .lineLimit(1)

            Spacer(minLength: 8)

            Menu {
                ForEach(settings.jiraProfiles) { profile in
                    Button {
                        settings.activateProfile(id: profile.id)
                    } label: {
                        if profile.id == settings.activeJiraProfileID {
                            Label("\(profile.name) (\(profile.projectKey))", systemImage: "checkmark")
                        } else {
                            Text("\(profile.name) (\(profile.projectKey))")
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(activeProfileText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 230)
        }
        .panelStyle()
    }

    private func readinessRow(title: String, value: String, isReady: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? appAccent : Color.secondary.opacity(0.65))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(minHeight: 46)
    }

    private var instructionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Reporter notes", systemImage: "text.alignleft")
                    .font(.headline)

                Spacer()

                Text("\(vm.hintText.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $vm.hintText)
                .frame(minHeight: 118)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if vm.hintText.isEmpty {
                        Text("What happened? What should Jira know?")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .panelStyle()
    }

    private var shouldShowFloatingDrawButton: Bool {
        vm.enableMarkup && vm.mediaItems.contains { $0.isImage }
    }

    private var markupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Highlight", systemImage: "pencil.and.outline")
                    .font(.headline)

                Spacer()

                Toggle("Enable", isOn: $vm.enableMarkup)
                    .labelsHidden()
            }

            if vm.enableMarkup {
                HStack(spacing: 10) {
                    markupColorPalette
                }

                Text(vm.isMarkupDrawingMode ? "Drawing mode active" : "Turn on drawing, then mark the screenshot area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(vm.mediaItems) { media in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(media.fileName, systemImage: media.isImage ? "photo" : "video.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            if media.isImage {
                                Button {
                                    vm.undoMark(mediaID: media.id)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Undo markup")

                                Button {
                                    vm.clearMarks(mediaID: media.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Clear markup")
                            }
                        }

                        ZoomableAnnotationCanvasView(
                            image: media.previewImage,
                            marks: vm.marksByMediaID[media.id] ?? [],
                            interactive: media.isImage && vm.isMarkupDrawingMode,
                            opacity: vm.markupOpacity
                        ) { point, isStart in
                            vm.addFreehandPoint(mediaID: media.id, normalizedPoint: point, beginStroke: isStart)
                        }

                        if !media.isImage {
                            Text("Markup is available for images only.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("Optional marks help the AI focus on the broken area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: vm.issueURL == nil ? "waveform.path.ecg" : "checkmark.circle.fill")
                    .foregroundStyle(vm.issueURL == nil ? Color.blue : appAccent)

                Text(vm.status)
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)

                Spacer()
            }

            if let issueURL = vm.issueURL {
                HStack(spacing: 14) {
                    Link(destination: issueURL) {
                        Label("Open Jira Issue", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        UIPasteboard.general.string = issueURL.absoluteString
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.footnote.weight(.medium))

                Text(issueURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                UIPasteboard.general.string = vm.status
            } label: {
                Label("Copy Message", systemImage: "doc.on.doc")
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .panelStyle()
    }

    private var submitBar: some View {
        VStack(spacing: 10) {
            Divider()

            if shouldShowSubmitProgress {
                submitProgressRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                Task { await vm.submit(settings: settings) }
            } label: {
                HStack(spacing: 10) {
                    if vm.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }

                    Text(submitTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue)
            .disabled(isSubmitDisabled)

            Text(submitHelperText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: shouldShowSubmitProgress)
    }

    private var submitProgressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                if vm.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: vm.issueURL == nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(vm.issueURL == nil ? Color.orange : appAccent)
                }

                Text(submitProgressText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            if let issueURL = vm.issueURL {
                HStack(spacing: 12) {
                    Link(destination: issueURL) {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        UIPasteboard.general.string = issueURL.absoluteString
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
    }

    private var activeJiraProfileSelection: Binding<String> {
        Binding(
            get: { settings.activeJiraProfileID },
            set: { settings.activateProfile(id: $0) }
        )
    }

    private var markupColorPalette: some View {
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

    private var floatingDrawButton: some View {
        Button {
            vm.isMarkupDrawingMode.toggle()
        } label: {
            Label("Draw", systemImage: "pencil")
                .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(vm.isMarkupDrawingMode ? appAccent : .secondary)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .accessibilityHint(vm.isMarkupDrawingMode ? "Drawing mode is active" : "Turns on drawing mode")
    }

    private var hasJiraConnection: Bool {
        !settings.workspaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mediaSummaryText: String {
        if vm.isLoadingMedia {
            return "Loading selected media..."
        }
        if vm.mediaItems.isEmpty {
            return "Start with the evidence for the bug."
        }
        return "\(vm.mediaItems.count) of 3 attachments selected"
    }

    private var activeProfileText: String {
        guard let profile = settings.activeJiraProfile else {
            return "No Jira profile selected"
        }
        return "\(profile.name) - \(profile.projectKey)"
    }

    private var credentialStatusText: String {
        switch (hasJiraConnection, !settings.openAIKey.isEmpty) {
        case (true, true):
            return "Jira and OpenAI are configured"
        case (false, true):
            return "Jira connection is missing"
        case (true, false):
            return "OpenAI key is missing"
        case (false, false):
            return "Jira and OpenAI settings are missing"
        }
    }

    private var isSubmitDisabled: Bool {
        vm.isSubmitting || vm.isLoadingMedia || vm.mediaItems.isEmpty || !settings.isConfigured
    }

    private var shouldShowSubmitProgress: Bool {
        vm.isSubmitting || vm.issueURL != nil || vm.status.hasPrefix("Failed:")
    }

    private var submitProgressText: String {
        vm.status.isEmpty ? "Preparing Jira ticket..." : vm.status
    }

    private var submitTitle: String {
        vm.isSubmitting ? "Creating Jira Ticket" : "Create Jira Ticket"
    }

    private var submitHelperText: String {
        if vm.mediaItems.isEmpty {
            return "Select screenshots or videos first."
        }
        if !settings.isConfigured {
            return "Complete Jira profile and OpenAI settings in Settings."
        }
        return "AI drafts the ticket and uploads the selected media."
    }
}

private struct CapturePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(CapturePanelModifier())
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

        let drawPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDrawPan(_:)))
        drawPan.minimumNumberOfTouches = 1
        drawPan.maximumNumberOfTouches = 1
        drawPan.cancelsTouchesInView = true
        drawingView.addGestureRecognizer(drawPan)

        context.coordinator.drawingView = drawingView
        context.coordinator.drawPanGesture = drawPan
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
        context.coordinator.isDrawingEnabled = interactive
        context.coordinator.drawPanGesture?.isEnabled = interactive

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
        weak var drawPanGesture: UIPanGestureRecognizer?
        var isDrawingEnabled = false
        private var isDrawingStrokeActive = false

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

        @objc func handleDrawPan(_ recognizer: UIPanGestureRecognizer) {
            guard isDrawingEnabled, let drawingView = drawingView else {
                isDrawingStrokeActive = false
                return
            }

            let point = recognizer.location(in: drawingView)
            guard let normalized = drawingView.normalizedPoint(point) else {
                if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                    isDrawingStrokeActive = false
                }
                return
            }

            switch recognizer.state {
            case .began:
                drawingView.onFreehandPoint?(normalized, true)
                isDrawingStrokeActive = true
            case .changed:
                if !isDrawingStrokeActive {
                    drawingView.onFreehandPoint?(normalized, true)
                    isDrawingStrokeActive = true
                } else {
                    drawingView.onFreehandPoint?(normalized, false)
                }
            case .ended:
                if isDrawingStrokeActive {
                    drawingView.onFreehandPoint?(normalized, false)
                }
                isDrawingStrokeActive = false
            case .cancelled, .failed:
                isDrawingStrokeActive = false
            default:
                break
            }
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

    func normalizedPoint(_ point: CGPoint) -> CGPoint? {
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
