import Foundation
import Security

enum KeychainKey: String {
    case jiraEmail = "jira_email"
    case jiraApiToken = "jira_api_token"
    case openAIKey = "openai_key"
}

enum KeychainError: Error {
    case unhandled(status: OSStatus)
}

final class KeychainService {
    static let shared = KeychainService()

    private init() {}

    func save(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    func read(_ key: KeychainKey) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }
}
