import Foundation

/// Bundles the bookmark + highlight sync engines behind one start/stop/push surface,
/// so the app drives annotation sync with a single handle (mirroring how the reading-
/// position engine is driven).
public struct AnnotationSyncEngines: Sendable {
    public let bookmarks: CollectionSyncEngine<Bookmark>
    public let highlights: CollectionSyncEngine<Highlight>

    public init(bookmarks: CollectionSyncEngine<Bookmark>, highlights: CollectionSyncEngine<Highlight>) {
        self.bookmarks = bookmarks
        self.highlights = highlights
    }

    public func start(userID: String) async {
        await bookmarks.start(userID: userID)
        await highlights.start(userID: userID)
    }

    public func stop() async {
        await bookmarks.stop()
        await highlights.stop()
    }

    public func pushDirty() async {
        await bookmarks.pushDirty()
        await highlights.pushDirty()
    }

    public func reconcile() async {
        await bookmarks.reconcile()
        await highlights.reconcile()
    }
}
