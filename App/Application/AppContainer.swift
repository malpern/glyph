import Foundation
import SwiftUI
import Observation
import ReaderCore

/// The composition root. Builds the concrete store, storage, and services once at
/// launch and hands out the protocol-typed dependencies the features need. This
/// is the single place that knows which implementations are wired in — swapping
/// the persistence engine or adding a sync-aware store happens only here.
///
/// Injected with SwiftUI's `@Observable` object environment
/// (`.environment(container)` / `@Environment(AppContainer.self)`).
@MainActor
@Observable
final class AppContainer {
    let store: SwiftDataStore
    let storage: BookStorage
    /// Reconciles local reading positions with the cloud. Started in `startSync()`.
    let syncEngine: ReadingStateSyncEngine
    /// Reconciles bookmarks + highlights with the cloud. Started in `startSync()`.
    let annotationSync: AnnotationSyncEngines
    /// App-wide reading appearance (theme/font/size/spacing).
    let readerSettings = ReaderSettingsStore()

    /// Key-based identity: the app derives a real Firebase login from a sync key
    /// the user moves between devices. Exposed so the sync settings UI can show /
    /// replace the key.
    let keyAuth = FirebaseKeyAuth(keyStore: KeychainKeyStore())

    /// Features depend on the protocols, not the concrete `SwiftDataStore`.
    var library: any LibraryRepository { store }
    var readingState: any ReadingStateRepository { store }

    init() {
        let stack: (store: SwiftDataStore, storage: BookStorage)
        do {
            stack = (try ReaderStore.make(), try BookStorage())
        } catch {
            // The on-disk store failed (corrupt/migration/disk) — fall back to an
            // in-memory store so the app still launches (without persistence).
            assertionFailure("Failed to build persistent stack: \(error)")
            do {
                stack = (try ReaderStore.make(inMemory: true), try BookStorage())
            } catch {
                // An in-memory store failing is unrecoverable; trap with a diagnosable
                // message rather than a bare try! so crash reports are actionable.
                fatalError("Glyph could not initialize storage (even in-memory): \(error)")
            }
        }
        self.store = stack.store
        self.storage = stack.storage
        self.syncEngine = ReadingStateSyncEngine(store: stack.store, remote: FirebaseSyncClient())
        self.annotationSync = Self.makeAnnotationSync(store: stack.store)
    }

    /// Build the bookmark + highlight sync engines: closures bridge the local store's
    /// sync methods to the Firestore annotation client. Keeps `ReaderCore` backend-agnostic.
    private static func makeAnnotationSync(store: SwiftDataStore) -> AnnotationSyncEngines {
        let client = FirebaseAnnotationClient()
        let bookmarks = CollectionSyncEngine<Bookmark>(
            store: .init(
                dirty: { try await store.dirtyBookmarks() },
                applyRemote: { try await store.applyRemoteBookmark($0) },
                clearDirty: { try await store.clearBookmarkDirty(id: $0, ifUpdatedAt: $1) }
            ),
            transport: .init(
                push: { try await client.pushBookmarks($0, userID: $1) },
                fetchAll: { try await client.fetchBookmarks(userID: $0) },
                observe: { client.observeBookmarks(userID: $0) }
            )
        )
        let highlights = CollectionSyncEngine<Highlight>(
            store: .init(
                dirty: { try await store.dirtyHighlights() },
                applyRemote: { try await store.applyRemoteHighlight($0) },
                clearDirty: { try await store.clearHighlightDirty(id: $0, ifUpdatedAt: $1) }
            ),
            transport: .init(
                push: { try await client.pushHighlights($0, userID: $1) },
                fetchAll: { try await client.fetchHighlights(userID: $0) },
                observe: { client.observeHighlights(userID: $0) }
            )
        )
        return AnnotationSyncEngines(bookmarks: bookmarks, highlights: highlights)
    }

    /// Drive the sync engine from auth state: start on sign-in, stop on sign-out.
    func startSync() async {
        for await userID in keyAuth.userIDs() {
            if let userID {
                await syncEngine.start(userID: userID)
                await annotationSync.start(userID: userID)
            } else {
                await syncEngine.stop()
                await annotationSync.stop()
            }
        }
    }

    func makeImporter() -> BookImporter {
        BookImporter(library: store, storage: storage)
    }
}
