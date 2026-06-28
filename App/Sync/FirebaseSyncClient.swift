import Foundation
import CryptoKit
@preconcurrency import FirebaseFirestore
import ReaderCore

/// `RemoteSyncClient` backed by Cloud Firestore. This is the only place Firebase
/// touches the sync path; `ReaderCore` and the engine stay backend-agnostic.
///
/// Layout: `users/{userID}/readingStates/{sha256(bookID)}` with fields
/// `{ bookID, locator (base64), updatedAt (epoch millis) }`. `updatedAt` is stored
/// as portable integer millis so last-writer-wins is comparable across platforms.
///
/// `@unchecked Sendable`: `Firestore` is internally thread-safe and the client
/// holds no mutable state of its own.
final class FirebaseSyncClient: RemoteSyncClient, @unchecked Sendable {
    private let db = Firestore.firestore()

    private func collection(_ userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("readingStates")
    }

    /// Push each dirty state inside a per-document transaction that enforces
    /// last-writer-wins remotely — so a slow/stale push can never overwrite a
    /// newer remote position.
    func push(_ states: [ReadingState], userID: String) async throws {
        let col = collection(userID)
        for state in states {
            let ref = col.document(Self.docID(for: state.bookID))
            let payload: [String: Any] = [
                "bookID": state.bookID,
                "locator": state.locator?.base64EncodedString() ?? "",
                "updatedAt": Self.millis(state.updatedAt),
            ]
            let localMillis = Self.millis(state.updatedAt)
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(ref)
                    if let remote = (snapshot.data()?["updatedAt"] as? NSNumber)?.int64Value,
                       remote >= localMillis {
                        return nil   // remote is newer-or-equal; leave it
                    }
                    transaction.setData(payload, forDocument: ref)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                }
                return nil
            }
        }
    }

    func fetchAll(userID: String) async throws -> [ReadingState] {
        let snapshot = try await collection(userID).getDocuments()
        return snapshot.documents.compactMap { Self.readingState(from: $0.data()) }
    }

    func observe(userID: String) -> AsyncThrowingStream<[ReadingState], Error> {
        let col = collection(userID)
        return AsyncThrowingStream { continuation in
            // ListenerRegistration isn't Sendable but its `remove()` is thread-safe;
            // capturing it in the @Sendable onTermination closure is safe here.
            nonisolated(unsafe) let registration = col.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                let states = snapshot.documentChanges
                    .filter { $0.type == .added || $0.type == .modified }
                    .compactMap { Self.readingState(from: $0.document.data()) }
                if !states.isEmpty { continuation.yield(states) }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: - Mapping

    private static func readingState(from data: [String: Any]) -> ReadingState? {
        guard let bookID = data["bookID"] as? String,
              let millis = (data["updatedAt"] as? NSNumber)?.int64Value else { return nil }
        let locatorString = data["locator"] as? String ?? ""
        let locator = locatorString.isEmpty ? nil : Data(base64Encoded: locatorString)
        return ReadingState(
            bookID: bookID,
            locator: locator,
            updatedAt: date(from: millis),
            bookmarks: [],
            highlights: [],
            pendingSync: false
        )
    }

    private static func docID(for bookID: String) -> String {
        SHA256.hash(data: Data(bookID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(from millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}
