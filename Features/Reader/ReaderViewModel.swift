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
    /// Text-to-speech for this session, created once the publication opens.
    private(set) var speech: SpeechController?
    /// X4 remote session (page-follow), wired to `speech`.
    private(set) var remoteSession: RemoteSessionController?

    private let fileURL: URL
    private let readingState: any ReadingStateRepository
    private let syncEngine: ReadingStateSyncEngine?
    private var saveTask: Task<Void, Never>?
    private var latestLocator: Locator?
    private var publication: Publication?
    /// Spine index of the page currently on screen — where read-aloud should begin.
    private var currentSpineIndex = 0

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
            self.publication = publication
            let initialLocator = await restoredLocator()
            if let initialLocator { currentSpineIndex = spineIndex(for: initialLocator) ?? 0 }
            let speechController = SpeechController(
                content: SpineContentProvider(fileURL: fileURL),
                bookTitle: book.title
            )
            speech = speechController
            remoteSession = RemoteSessionController(speech: speechController)
            state = .ready(publication, initialLocator: initialLocator)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Start / pause / resume read-aloud, beginning at the page on screen.
    func toggleSpeech() async {
        guard let speech else { return }
        if speech.isPlaying {
            speech.pause()
        } else if speech.paragraphOrdinal == 0 {
            await speech.start(spineIndex: currentSpineIndex)
        } else {
            speech.play()
        }
    }

    /// Called by the navigator on every position change. Debounced so a burst of
    /// page turns collapses into one write.
    func locationChanged(_ locator: Locator) {
        latestLocator = locator
        if let index = spineIndex(for: locator) { currentSpineIndex = index }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.persist(locator)
        }
    }

    /// Stop read-aloud and disconnect the X4 — call when leaving the reader.
    func stopAll() {
        speech?.tearDown()
        remoteSession?.stop()
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

    /// The spine (reading-order) index a locator points into, by normalized-URL match.
    private func spineIndex(for locator: Locator) -> Int? {
        guard let publication else { return nil }
        return publication.readingOrder.firstIndex { locator.href.isEquivalentTo($0.url()) }
    }

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
