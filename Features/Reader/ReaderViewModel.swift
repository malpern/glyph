import Foundation
import Observation
import ReadiumShared
import ReaderCore

/// Owns a reading session: opens the publication, restores the saved position,
/// and persists position changes. The persistence target is the
/// `ReadingStateRepository` protocol — this is exactly the seam a future sync
/// engine plugs into, unchanged.
@MainActor
@Observable
final class ReaderViewModel {
    enum State {
        case loading
        case ready(Publication, initialLocator: Locator?)
        case failed(String)
    }

    let book: Book
    private(set) var state: State = .loading

    private let fileURL: URL
    private let readingState: any ReadingStateRepository
    private let syncEngine: ReadingStateSyncEngine?
    private var saveTask: Task<Void, Never>?
    private var latestLocator: Locator?

    init(
        book: Book,
        fileURL: URL,
        readingState: any ReadingStateRepository,
        syncEngine: ReadingStateSyncEngine? = nil
    ) {
        self.book = book
        self.fileURL = fileURL
        self.readingState = readingState
        self.syncEngine = syncEngine
    }

    func load() async {
        do {
            let publication = try await ReadiumStack.open(at: fileURL)
            state = .ready(publication, initialLocator: await restoredLocator())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Called by the navigator on every position change. Debounced so a burst of
    /// page turns collapses into one write.
    func locationChanged(_ locator: Locator) {
        latestLocator = locator
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.persist(locator)
        }
    }

    /// Flush the latest position immediately — call before dismissing so resume is
    /// exact even if the debounce hasn't fired.
    func flush() async {
        saveTask?.cancel()
        if let latestLocator {
            await persist(latestLocator)
        }
    }

    // MARK: -

    private func restoredLocator() async -> Locator? {
        guard
            let state = (try? await readingState.readingState(bookID: book.id)) ?? nil,
            let data = state.locator
        else { return nil }
        return LocatorCoding.locator(from: data)
    }

    private func persist(_ locator: Locator) async {
        guard let data = LocatorCoding.data(from: locator) else { return }
        try? await readingState.updateLocator(bookID: book.id, locator: data)
        await syncEngine?.pushDirty()   // propagate to other devices promptly
    }
}
