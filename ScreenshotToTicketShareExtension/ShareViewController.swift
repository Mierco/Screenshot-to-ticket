import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var hasStartedImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStartedImport else { return }
        hasStartedImport = true

        Task {
            await importSharedMedia()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.text = "Importing shared media..."

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.configuration = .filled()
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)
        closeButton.isHidden = true

        view.addSubview(activityIndicator)
        view.addSubview(messageLabel)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),

            messageLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            closeButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @MainActor
    private func importSharedMedia() async {
        setLoadingState(message: "Importing shared media...")

        do {
            let itemProviders = collectItemProviders()
            guard !itemProviders.isEmpty else {
                throw ShareImportError.noMedia
            }

            let batchDirectory = try SharedMediaInbox.createBatchDirectory()
            var importedCount = 0
            var skippedCount = 0

            for (index, itemProvider) in itemProviders.enumerated() {
                do {
                    if try await importItemProvider(itemProvider, index: index, into: batchDirectory) {
                        importedCount += 1
                    } else {
                        skippedCount += 1
                    }
                } catch {
                    skippedCount += 1
                }
            }

            guard importedCount > 0 else {
                try? FileManager.default.removeItem(at: batchDirectory)
                throw ShareImportError.unsupportedContent
            }

            if skippedCount > 0 {
                SharedMediaInbox.setPendingImportNotice("Some shared items could not be imported.")
            } else {
                SharedMediaInbox.setPendingImportNotice(nil)
            }

            setLoadingState(message: "Opening ScreenshotToTicket...")

            if openContainingApp() {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } else {
                showResult(
                    message: "Media was imported. Open ScreenshotToTicket to continue.",
                    showsCloseButton: true
                )
            }
        } catch {
            SharedMediaInbox.setPendingImportNotice(nil)
            showResult(message: error.localizedDescription, showsCloseButton: true)
        }
    }

    private func collectItemProviders() -> [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    private func importItemProvider(
        _ itemProvider: NSItemProvider,
        index: Int,
        into batchDirectory: URL
    ) async throws -> Bool {
        guard let contentType = supportedContentType(for: itemProvider) else {
            return false
        }

        let preferredFileName = makePreferredFileName(
            baseName: itemProvider.suggestedName ?? "shared-item-\(index + 1)",
            contentType: contentType
        )

        if await storeFileRepresentation(
            from: itemProvider,
            contentType: contentType,
            in: batchDirectory,
            preferredFileName: preferredFileName
        ) {
            return true
        }

        if let data = try await loadDataRepresentation(from: itemProvider, contentType: contentType) {
            try SharedMediaInbox.storeImportedData(
                data,
                in: batchDirectory,
                preferredFileName: preferredFileName
            )
            return true
        }

        return false
    }

    private func supportedContentType(for itemProvider: NSItemProvider) -> UTType? {
        let contentTypes = itemProvider.registeredTypeIdentifiers.compactMap(UTType.init)
        return contentTypes.first {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .audiovisualContent)
        } ?? contentTypes.first {
            $0.conforms(to: .image)
        }
    }

    private func storeFileRepresentation(
        from itemProvider: NSItemProvider,
        contentType: UTType,
        in batchDirectory: URL,
        preferredFileName: String
    ) async -> Bool {
        guard itemProvider.hasItemConformingToTypeIdentifier(contentType.identifier) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: contentType.identifier) { url, error in
                guard error == nil, let url else {
                    continuation.resume(returning: false)
                    return
                }

                do {
                    try SharedMediaInbox.storeImportedFile(
                        from: url,
                        in: batchDirectory,
                        preferredFileName: preferredFileName
                    )
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func loadDataRepresentation(
        from itemProvider: NSItemProvider,
        contentType: UTType
    ) async throws -> Data? {
        guard itemProvider.hasItemConformingToTypeIdentifier(contentType.identifier) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func makePreferredFileName(baseName: String, contentType: UTType) -> String {
        let extensionPart = contentType.preferredFilenameExtension
            ?? (contentType.conforms(to: .image) ? "jpg" : "mov")
        let base = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
        return "\(base).\(extensionPart)"
    }

    @MainActor
    private func setLoadingState(message: String) {
        activityIndicator.startAnimating()
        messageLabel.text = message
        closeButton.isHidden = true
    }

    @MainActor
    private func showResult(message: String, showsCloseButton: Bool) {
        activityIndicator.stopAnimating()
        messageLabel.text = message
        closeButton.isHidden = !showsCloseButton
    }

    private func openContainingApp() -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                _ = currentResponder.perform(selector, with: SharedMediaInbox.importTriggerURL())
                return true
            }
            responder = currentResponder.next
        }

        return false
    }

    @objc
    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

private enum ShareImportError: LocalizedError {
    case noMedia
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .noMedia:
            return "No media was shared with ScreenshotToTicket."
        case .unsupportedContent:
            return "Only photos and videos can be shared to ScreenshotToTicket."
        }
    }
}
