import Foundation
@preconcurrency import FirebaseAuth
import ReaderCore

/// `AuthProviding` backed by Firebase Email/Password, driven entirely by the sync
/// key. The user never sees or types the derived email/password — they only ever
/// handle the key. Switching keys re-authenticates to a different account.
///
/// `@unchecked Sendable`: holds only an immutable key store; `FirebaseAuth` is
/// itself thread-safe.
final class FirebaseKeyAuth: AuthProviding, @unchecked Sendable {
    private let keyStore: KeychainKeyStore

    init(keyStore: KeychainKeyStore) {
        self.keyStore = keyStore
    }

    func userIDs() -> AsyncStream<String?> {
        AsyncStream { continuation in
            nonisolated(unsafe) let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield(user?.uid)
            }
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
            // Kick off (or refresh) sign-in from the stored key.
            Task { await self.signInWithStoredKey() }
        }
    }

    /// The current sync key for display / QR (generates one on first use).
    func currentKey() -> String {
        keyStore.loadOrCreate()
    }

    /// Adopt a key from another device and re-authenticate to its account.
    func useKey(_ key: String) async {
        keyStore.save(key)
        try? Auth.auth().signOut()
        await signInWithStoredKey()
    }

    // MARK: -

    private func signInWithStoredKey() async {
        let credentials = SyncKey.credentials(for: keyStore.loadOrCreate())
        if let user = Auth.auth().currentUser, user.email == credentials.email {
            return   // already on the right account
        }
        do {
            try await Auth.auth().signIn(withEmail: credentials.email, password: credentials.password)
        } catch {
            // Expected on first use for this key: the account doesn't exist yet.
            do {
                try await Auth.auth().createUser(withEmail: credentials.email, password: credentials.password)
            } catch {
                _ = try? await Auth.auth().signIn(withEmail: credentials.email, password: credentials.password)
            }
        }
    }
}
