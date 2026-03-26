import Foundation

enum AppBuildInfo {
    private struct BuildMetadata: Decodable {
        let buildNumber: String
        let gitCommitSHA: String
    }

    private static let metadata: BuildMetadata? = {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BuildMetadata.self, from: data)
    }()

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        metadata?.buildNumber
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
    }

    static var gitCommitSHA: String? {
        guard let value = metadata?.gitCommitSHA,
              !value.isEmpty,
              value != "unknown" else {
            return nil
        }
        return value
    }

    static var badgeText: String {
        if let gitCommitSHA {
            return "v\(shortVersion) (\(buildNumber)) \(gitCommitSHA)"
        }
        return "v\(shortVersion) (\(buildNumber))"
    }
}
