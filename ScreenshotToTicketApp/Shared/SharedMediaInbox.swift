import Foundation

enum SharedMediaInbox {
    static let appGroupIdentifier = "group.com.iagentur.screenshottoticket"
    static let importURLScheme = "screenshottoticket"
    static let importURLHost = "shared-media"

    private static let inboxDirectoryName = "SharedMediaInbox"
    private static let noticeKey = "pendingShareImportNotice"

    enum InboxError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The app could not access its shared media container."
            }
        }
    }

    static func importTriggerURL() -> URL {
        URL(string: "\(importURLScheme)://\(importURLHost)")!
    }

    static func matchesImportTrigger(_ url: URL) -> Bool {
        url.scheme == importURLScheme && url.host == importURLHost
    }

    static func hasPendingMedia() -> Bool {
        (try? !pendingBatchDirectories().isEmpty) ?? false
    }

    static func createBatchDirectory() throws -> URL {
        let inboxRoot = try inboxRootURL()
        let batchDirectory = inboxRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        return batchDirectory
    }

    @discardableResult
    static func storeImportedFile(
        from sourceURL: URL,
        in batchDirectory: URL,
        preferredFileName: String? = nil
    ) throws -> URL {
        let fileName = sanitizedFileName(
            preferredFileName
            ?? sourceURL.lastPathComponent
        )
        let destinationURL = uniqueDestinationURL(in: batchDirectory, fileName: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    @discardableResult
    static func storeImportedData(
        _ data: Data,
        in batchDirectory: URL,
        preferredFileName: String
    ) throws -> URL {
        let destinationURL = uniqueDestinationURL(
            in: batchDirectory,
            fileName: sanitizedFileName(preferredFileName)
        )
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func takePendingFiles() throws -> [URL] {
        let batchDirectories = try pendingBatchDirectories()
        guard !batchDirectories.isEmpty else { return [] }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedMediaImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        var stagedFiles: [URL] = []
        for batchDirectory in batchDirectories {
            let files = try childFiles(in: batchDirectory)
            for fileURL in files {
                let destinationURL = uniqueDestinationURL(
                    in: stagingRoot,
                    fileName: fileURL.lastPathComponent
                )
                try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                stagedFiles.append(destinationURL)
            }
            try? FileManager.default.removeItem(at: batchDirectory)
        }

        return stagedFiles
    }

    static func setPendingImportNotice(_ notice: String?) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        if let notice, !notice.isEmpty {
            defaults?.set(notice, forKey: noticeKey)
        } else {
            defaults?.removeObject(forKey: noticeKey)
        }
    }

    static func consumePendingImportNotice() -> String? {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let notice = defaults?.string(forKey: noticeKey)
        defaults?.removeObject(forKey: noticeKey)
        return notice
    }

    private static func inboxRootURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw InboxError.unavailable
        }

        let inboxURL = containerURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        return inboxURL
    }

    private static func pendingBatchDirectories() throws -> [URL] {
        let directoryKeys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        return try FileManager.default.contentsOfDirectory(
            at: inboxRootURL(),
            includingPropertiesForKeys: Array(directoryKeys),
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: directoryKeys).isDirectory) ?? false
        }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: directoryKeys).creationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: directoryKeys).creationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            return lhsDate < rhsDate
        }
    }

    private static func childFiles(in directory: URL) throws -> [URL] {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return fileURLs
        .filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false
        }
        .sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func uniqueDestinationURL(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let baseURL = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension

        for index in 2...Int.max {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent(UUID().uuidString)
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = trimmed.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }
}
