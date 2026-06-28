import Foundation
import Security

/// Persists the sync key in the Keychain (a credential belongs there, not in
/// UserDefaults), with a UserDefaults fallback so it can never hard-fail, and a
/// DEBUG env override so the two-simulator test can inject one shared key.
final class KeychainKeyStore: @unchecked Sendable {
    private let service = "dev.malpern.Reader.sync"
    private let account = "sync-key"
    private let defaultsKey = "reader.sync.key"

    /// The current key, generating and storing one on first use.
    func loadOrCreate() -> String {
        #if DEBUG
        if let injected = ProcessInfo.processInfo.environment["READER_SYNC_KEY"],
           !injected.isEmpty {
            return injected
        }
        #endif
        if let existing = load() { return existing }
        let key = SyncKey.generate()
        save(key)
        return key
    }

    func save(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(key, forKey: defaultsKey)   // fallback
        }
    }

    private func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }
}
