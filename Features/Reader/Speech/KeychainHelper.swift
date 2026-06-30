import Foundation
import Security

/// Minimal Keychain wrapper for the user's TTS provider API keys. Keys are sensitive,
/// so they live in the Keychain (not UserDefaults). One generic-password item per
/// provider account ("openai" / "elevenlabs").
enum KeychainHelper {
    private static let service = "dev.malpern.Glyph.apiKeys"

    static func save(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return }   // empty = clear the key
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    static func hasKey(account: String) -> Bool {
        (read(account: account)?.isEmpty == false)
    }

    enum Account {
        static let openAI = "openai"
        static let elevenLabs = "elevenlabs"
    }
}
