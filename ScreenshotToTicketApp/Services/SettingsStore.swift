import Foundation

enum AppLanguageCode: String, CaseIterable {
    case en
    case de
    case it
}

enum AppLanguagePreference: String, CaseIterable {
    case system
    case en
    case de
    case it

    init(storedValue: String?) {
        let normalizedValue = storedValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self = AppLanguagePreference(rawValue: normalizedValue ?? "") ?? .system
    }

    var overrideLanguageCode: AppLanguageCode? {
        AppLanguageCode(rawValue: rawValue)
    }

    var persistedValue: String? {
        self == .system ? nil : rawValue
    }
}

enum AppLanguageResolver {
    static func resolveEffectiveLanguage(
        storedPreference: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguageCode {
        resolveEffectiveLanguage(
            languagePreference: AppLanguagePreference(storedValue: storedPreference),
            preferredLanguages: preferredLanguages
        )
    }

    static func resolveEffectiveLanguage(
        languagePreference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguageCode {
        if let overrideLanguage = languagePreference.overrideLanguageCode {
            return overrideLanguage
        }

        for preferredLanguage in preferredLanguages {
            guard let normalizedCode = normalizedLanguageCode(from: preferredLanguage),
                  let matchedLanguage = AppLanguageCode(rawValue: normalizedCode) else {
                continue
            }

            return matchedLanguage
        }

        return .en
    }

    static func normalizedLanguageCode(from languageIdentifier: String) -> String? {
        let normalizedIdentifier = languageIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        guard !normalizedIdentifier.isEmpty else {
            return nil
        }

        return normalizedIdentifier
            .split(separator: "-")
            .first
            .map(String.init)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let workspaceURLKey = "workspaceURL"
    private static let projectKeyKey = "projectKey"
    private static let openAIModelKey = "openaiModel"
    private static let languagePreferenceKey = "appLanguagePreference"

    @Published var jiraEmail: String
    @Published var jiraApiToken: String
    @Published var openAIKey: String
    @Published var workspaceURL: String
    @Published var projectKey: String
    @Published var model: String
    @Published var languagePreference: AppLanguagePreference {
        didSet {
            effectiveLanguage = resolvedEffectiveLanguage()
        }
    }
    @Published private(set) var effectiveLanguage: AppLanguageCode

    private let defaults: UserDefaults
    private let preferredLanguagesProvider: () -> [String]

    init(
        defaults: UserDefaults = .standard,
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguagesProvider = preferredLanguagesProvider

        jiraEmail = KeychainService.shared.read(.jiraEmail)
        jiraApiToken = KeychainService.shared.read(.jiraApiToken)
        openAIKey = KeychainService.shared.read(.openAIKey)

        workspaceURL = defaults.string(forKey: Self.workspaceURLKey) ?? "https://iagentur.jira.com"
        projectKey = defaults.string(forKey: Self.projectKeyKey) ?? "TMNEWS"
        model = defaults.string(forKey: Self.openAIModelKey) ?? "gpt-5.4-codex"

        let storedLanguagePreference = AppLanguagePreference(
            storedValue: defaults.string(forKey: Self.languagePreferenceKey)
        )
        languagePreference = storedLanguagePreference
        effectiveLanguage = AppLanguageResolver.resolveEffectiveLanguage(
            languagePreference: storedLanguagePreference,
            preferredLanguages: preferredLanguagesProvider()
        )
    }

    func save() throws {
        projectKey = projectKey.uppercased()
        try KeychainService.shared.save(jiraEmail, for: .jiraEmail)
        try KeychainService.shared.save(jiraApiToken, for: .jiraApiToken)
        try KeychainService.shared.save(openAIKey, for: .openAIKey)

        defaults.set(workspaceURL, forKey: Self.workspaceURLKey)
        defaults.set(projectKey, forKey: Self.projectKeyKey)
        defaults.set(model, forKey: Self.openAIModelKey)

        if let persistedLanguagePreference = languagePreference.persistedValue {
            defaults.set(persistedLanguagePreference, forKey: Self.languagePreferenceKey)
        } else {
            defaults.removeObject(forKey: Self.languagePreferenceKey)
        }
    }

    func refreshEffectiveLanguage(preferredLanguages: [String]? = nil) {
        effectiveLanguage = AppLanguageResolver.resolveEffectiveLanguage(
            languagePreference: languagePreference,
            preferredLanguages: preferredLanguages ?? preferredLanguagesProvider()
        )
    }

    var effectiveLocale: Locale {
        Locale(identifier: effectiveLanguage.rawValue)
    }

    var isConfigured: Bool {
        !jiraEmail.isEmpty && !jiraApiToken.isEmpty && !openAIKey.isEmpty
    }

    private func resolvedEffectiveLanguage() -> AppLanguageCode {
        AppLanguageResolver.resolveEffectiveLanguage(
            languagePreference: languagePreference,
            preferredLanguages: preferredLanguagesProvider()
        )
    }
}
