import Foundation
import CryptoKit
import Security

/// The sync "key" model. A key is a high-entropy secret a user moves between
/// their devices (copy/paste, QR, or a file on the X4). The app turns it into a
/// real Firebase email+password **deterministically**, so:
/// - the same key on two devices → the same Firebase account → the same data,
/// - no human ever types a credential (only the key is moved), and
/// - security stays real (Firestore rules enforce `request.auth.uid`).
enum SyncKey {
    /// A fresh 160-bit key as lowercase hex (only 0-9a-f — clean for QR and display).
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Derive the Firebase credentials for a key. `.invalid` is the reserved TLD
    /// (RFC 2606) — these addresses never resolve and are never emailed.
    static func credentials(for key: String) -> (email: String, password: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let idHash = sha256Hex(normalized)
        let email = "k-\(idHash.prefix(32))@reader.invalid"
        let password = sha256Hex(normalized + ":pw")   // 64 hex chars, high-entropy
        return (email, password)
    }

    /// Human-friendlier grouping for display (does not change the key's value).
    static func grouped(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 4).map { i in
            let start = key.index(key.startIndex, offsetBy: i)
            let end = key.index(start, offsetBy: 4, limitedBy: key.endIndex) ?? key.endIndex
            return String(key[start..<end])
        }.joined(separator: " ")
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
