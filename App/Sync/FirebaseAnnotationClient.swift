import Foundation
@preconcurrency import FirebaseFirestore
import ReaderCore

/// Firestore transport for bookmarks + highlights, mirroring `FirebaseSyncClient`.
/// Layout: `users/{userID}/bookmarks/{id}` and `users/{userID}/highlights/{id}`,
/// keyed by the record's own UUID. Timestamps are portable epoch-millis so LWW is
/// comparable across platforms; `deletedAt` carries tombstones. Each push runs a
/// per-doc transaction enforcing last-writer-wins remotely.
///
/// `@unchecked Sendable`: `Firestore` is thread-safe and this holds no mutable state.
final class FirebaseAnnotationClient: @unchecked Sendable {
    private let db = Firestore.firestore()

    private func bookmarks(_ userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("bookmarks")
    }
    private func highlights(_ userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("highlights")
    }

    // MARK: Bookmarks

    func pushBookmarks(_ items: [Bookmark], userID: String) async throws {
        try await push(items.map { ($0.id.uuidString, Self.payload(bookmark: $0), Self.millis($0.updatedAt)) },
                       into: bookmarks(userID))
    }

    func fetchBookmarks(userID: String) async throws -> [Bookmark] {
        try await bookmarks(userID).getDocuments().documents.compactMap {
            Self.bookmark(id: $0.documentID, data: $0.data())
        }
    }

    func observeBookmarks(userID: String) -> AsyncThrowingStream<[Bookmark], Error> {
        let col = bookmarks(userID)
        return AsyncThrowingStream { continuation in
            nonisolated(unsafe) let registration = col.addSnapshotListener { snapshot, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snapshot else { return }
                let items = snapshot.documentChanges
                    .filter { $0.type == .added || $0.type == .modified }
                    .compactMap { Self.bookmark(id: $0.document.documentID, data: $0.document.data()) }
                if !items.isEmpty { continuation.yield(items) }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Highlights

    func pushHighlights(_ items: [Highlight], userID: String) async throws {
        try await push(items.map { ($0.id.uuidString, Self.payload(highlight: $0), Self.millis($0.updatedAt)) },
                       into: highlights(userID))
    }

    func fetchHighlights(userID: String) async throws -> [Highlight] {
        try await highlights(userID).getDocuments().documents.compactMap {
            Self.highlight(id: $0.documentID, data: $0.data())
        }
    }

    func observeHighlights(userID: String) -> AsyncThrowingStream<[Highlight], Error> {
        let col = highlights(userID)
        return AsyncThrowingStream { continuation in
            nonisolated(unsafe) let registration = col.addSnapshotListener { snapshot, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snapshot else { return }
                let items = snapshot.documentChanges
                    .filter { $0.type == .added || $0.type == .modified }
                    .compactMap { Self.highlight(id: $0.document.documentID, data: $0.document.data()) }
                if !items.isEmpty { continuation.yield(items) }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: - Shared push (per-doc LWW transaction)

    private func push(_ docs: [(id: String, payload: [String: Any], millis: Int64)], into col: CollectionReference) async throws {
        for doc in docs {
            let ref = col.document(doc.id)
            let localMillis = doc.millis
            let payload = doc.payload
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(ref)
                    if let remote = (snapshot.data()?["updatedAt"] as? NSNumber)?.int64Value,
                       remote >= localMillis {
                        return nil   // remote newer-or-equal; leave it
                    }
                    transaction.setData(payload, forDocument: ref)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                }
                return nil
            }
        }
    }

    // MARK: - Mapping

    private static func payload(bookmark b: Bookmark) -> [String: Any] {
        [
            "bookID": b.bookID,
            "locator": b.locator.base64EncodedString(),
            "createdAt": millis(b.createdAt),
            "updatedAt": millis(b.updatedAt),
            "deletedAt": b.deletedAt.map(millis) ?? NSNull(),
        ]
    }

    private static func payload(highlight h: Highlight) -> [String: Any] {
        var payload: [String: Any] = [
            "bookID": h.bookID,
            "locator": h.locator.base64EncodedString(),
            "createdAt": millis(h.createdAt),
            "updatedAt": millis(h.updatedAt),
            "deletedAt": h.deletedAt.map(millis) ?? NSNull(),
        ]
        payload["text"] = h.text ?? NSNull()
        payload["color"] = h.color ?? NSNull()
        return payload
    }

    private static func bookmark(id docID: String, data: [String: Any]) -> Bookmark? {
        guard let id = UUID(uuidString: docID),
              let bookID = data["bookID"] as? String,
              let updated = (data["updatedAt"] as? NSNumber)?.int64Value else { return nil }
        let created = (data["createdAt"] as? NSNumber)?.int64Value ?? updated
        return Bookmark(
            id: id, bookID: bookID,
            locator: Data(base64Encoded: data["locator"] as? String ?? "") ?? Data(),
            createdAt: date(from: created), updatedAt: date(from: updated),
            deletedAt: (data["deletedAt"] as? NSNumber).map { date(from: $0.int64Value) }
        )
    }

    private static func highlight(id docID: String, data: [String: Any]) -> Highlight? {
        guard let id = UUID(uuidString: docID),
              let bookID = data["bookID"] as? String,
              let updated = (data["updatedAt"] as? NSNumber)?.int64Value else { return nil }
        let created = (data["createdAt"] as? NSNumber)?.int64Value ?? updated
        return Highlight(
            id: id, bookID: bookID,
            locator: Data(base64Encoded: data["locator"] as? String ?? "") ?? Data(),
            text: data["text"] as? String,
            color: data["color"] as? String,
            createdAt: date(from: created), updatedAt: date(from: updated),
            deletedAt: (data["deletedAt"] as? NSNumber).map { date(from: $0.int64Value) }
        )
    }

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(from millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}
