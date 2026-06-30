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
    /// App-wide reader settings (read-aloud granularity). Attached before `load()`.
    private var settingsStore: ReaderSettingsStore?
    /// Bookmarks for this book (live; oldest first). Loaded on `load()`.
    private(set) var bookmarks: [Bookmark] = []
    /// Highlights for this book (live; oldest first). Loaded on `load()`.
    private(set) var highlights: [Highlight] = []
    /// Flattened, depth-tagged table of contents for the Contents sheet. Loaded on `load()`.
    private(set) var tableOfContents: [TOCEntry] = []
    /// One-shot navigator jump (tapping a bookmark). The token makes repeated jumps to
    /// the same locator distinct, so the navigator re-navigates each tap.
    private(set) var pendingJump: JumpRequest?
    private var jumpToken = 0

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

    /// Wire app-wide settings (read-aloud granularity). Call before `load()`.
    func attach(settings: ReaderSettingsStore) { settingsStore = settings }

    func load() async {
        do {
            let publication = try await ReadiumStack.open(at: fileURL)
            self.publication = publication
            let initialLocator = await restoredLocator()
            latestLocator = initialLocator   // a valid "current page" before the first move
            if let initialLocator { currentSpineIndex = spineIndex(for: initialLocator) ?? 0 }
            bookmarks = (try? await readingState.bookmarks(bookID: book.id)) ?? []
            highlights = (try? await readingState.highlights(bookID: book.id)) ?? []
            // TOC flattening happens in the nonisolated ReadiumStack helper so the
            // non-Sendable `Publication` never crosses into this @MainActor type.
            tableOfContents = (try? await ReadiumStack.tableOfContents(at: fileURL)) ?? []
            let engine = SpeechEngineFactory.make(from: settingsStore?.settings ?? ReaderSettings())
            let speechController = SpeechController(
                content: SpineContentProvider(fileURL: fileURL),
                bookTitle: book.title,
                engine: engine
            )
            speech = speechController
            let session = RemoteSessionController(
                speech: speechController,
                granularity: { [weak self] in self?.settingsStore?.settings.highlightGranularity ?? .sentence }
            )
            session.onRemotePosition = { [weak self] spine, para, bookID in
                Task { await self?.adoptRemotePosition(spine: spine, para: para, bookID: bookID) }
            }
            session.phonePosition = { [weak self] in await self?.currentRemotePosition() }
            remoteSession = session
            state = .ready(publication, initialLocator: initialLocator)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Read-aloud highlight + page-follow targets for the current sentence, by
    /// granularity. `highlight` is the decoration to draw (nil in `.page` mode);
    /// `follow` is the locator to keep on screen (page-follows even in `.page` mode).
    /// Both are text locators Readium resolves by fuzzy-matching in the page DOM, so
    /// no precise DOM range is needed. The follow cadence is the granularity: in
    /// `.paragraph`/`.page` the target only changes per paragraph, so the page turns
    /// at most once per paragraph instead of on every sentence.
    var ttsLocators: (highlight: Locator?, follow: Locator?) {
        guard let sentence = speech?.spokenSentence,
              let publication,
              publication.readingOrder.indices.contains(sentence.spineIndex)
        else { return (nil, nil) }
        let link = publication.readingOrder[sentence.spineIndex]
        func locator(_ text: String, before: String?, after: String?) -> Locator {
            Locator(
                href: link.url(),
                mediaType: link.mediaType ?? .html,
                text: .init(after: after, before: before, highlight: text)
            )
        }
        switch settingsStore?.settings.highlightGranularity ?? .sentence {
        case .sentence:
            let l = locator(sentence.sentenceText, before: sentence.before, after: sentence.after)
            return (l, l)
        case .paragraph:
            let l = locator(sentence.paragraphText, before: nil, after: nil)
            return (l, l)
        case .page:
            let l = locator(sentence.paragraphText, before: nil, after: nil)
            return (nil, l)
        case .off:
            return (nil, nil)   // audio only — no highlight, no follow
        }
    }

    // MARK: Bookmarks

    /// Bookmark the current page.
    func addBookmark() async {
        guard let locator = latestLocator, let data = LocatorCoding.data(from: locator) else { return }
        try? await readingState.addBookmark(Bookmark(bookID: book.id, locator: data))
        await reloadBookmarks()
    }

    func deleteBookmark(_ id: UUID) async {
        try? await readingState.deleteBookmark(id: id)
        await reloadBookmarks()
    }

    /// Jump the navigator to a bookmark's saved position.
    func jump(to bookmark: Bookmark) {
        guard let locator = LocatorCoding.locator(from: bookmark.locator) else { return }
        jumpToken += 1
        pendingJump = JumpRequest(locator: locator, token: jumpToken)
    }

    private func reloadBookmarks() async {
        bookmarks = (try? await readingState.bookmarks(bookID: book.id)) ?? []
    }

    // MARK: Table of contents

    /// The TOC entry the reader is currently inside — the deepest entry at or before the
    /// current position (by spine, then progression). Drives the "you are here" highlight.
    var currentTOCID: TOCEntry.ID? {
        let curSpine = currentSpineIndex
        let curProgression = latestLocator?.locations.progression ?? 0
        var best: TOCEntry?
        var bestKey = (-1, -1.0)
        for entry in tableOfContents {
            guard let spine = entry.spineIndex else { continue }
            let progression = entry.locator?.locations.progression ?? 0
            // Entry is at or before where we're reading?
            guard spine < curSpine || (spine == curSpine && progression <= curProgression + 0.0001)
            else { continue }
            if (spine, progression) > bestKey { bestKey = (spine, progression); best = entry }
        }
        return best?.id
    }

    /// Jump the navigator to a table-of-contents entry.
    func jump(toTOC entry: TOCEntry) {
        guard let locator = entry.locator else { return }
        jumpToken += 1
        pendingJump = JumpRequest(locator: locator, token: jumpToken)
    }


    // MARK: Highlights

    /// Saved highlights mapped to renderable decorations for the navigator.
    var highlightDecorations: [HighlightDecoration] {
        highlights.compactMap { h in
            guard let locator = LocatorCoding.locator(from: h.locator) else { return nil }
            return HighlightDecoration(id: h.id.uuidString, locator: locator, colorToken: h.color ?? "yellow")
        }
    }

    /// Create a highlight from a text selection's locator.
    func createHighlight(at locator: Locator, color: HighlightColor = .yellow) async {
        guard let data = LocatorCoding.data(from: locator) else { return }
        let highlight = Highlight(bookID: book.id, locator: data, text: locator.text.highlight, color: color.rawValue)
        try? await readingState.addHighlight(highlight)
        await reloadHighlights()
    }

    func deleteHighlight(_ id: UUID) async {
        try? await readingState.deleteHighlight(id: id)
        await reloadHighlights()
    }

    func recolorHighlight(_ id: UUID, to color: HighlightColor) async {
        guard var highlight = highlights.first(where: { $0.id == id }) else { return }
        highlight.color = color.rawValue
        try? await readingState.updateHighlight(highlight)
        await reloadHighlights()
    }

    /// Jump the navigator to a highlight's position.
    func jump(to highlight: Highlight) {
        guard let locator = LocatorCoding.locator(from: highlight.locator) else { return }
        jumpToken += 1
        pendingJump = JumpRequest(locator: locator, token: jumpToken)
    }

    private func reloadHighlights() async {
        highlights = (try? await readingState.highlights(bookID: book.id)) ?? []
    }

    #if DEBUG
    /// Create a highlight over `text` on the current page — lets headless simulator runs
    /// exercise the render path without a real text selection.
    func debugCreateHighlight(text: String) async {
        guard let base = latestLocator else { return }
        let locator = Locator(href: base.href, mediaType: base.mediaType, text: .init(highlight: text))
        await createHighlight(at: locator)
    }
    #endif

    /// Apply a live TTS provider/voice change to the open session (rebuilds the engine).
    func rebuildSpeechEngine() {
        guard let settings = settingsStore?.settings else { return }
        speech?.setEngine(SpeechEngineFactory.make(from: settings))
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

    /// Bridge: the X4 user turned a page with the physical buttons (`pos`) — they took
    /// control. Pause read-aloud, follow the navigator to that position, and mirror it
    /// into the synced `ReadingState` (last-writer-wins) so this phone's next open, and
    /// the user's other Glyph devices, resume there.
    private func adoptRemotePosition(spine: Int, para: Int, bookID: String?) async {
        guard RemotePositionMapping.appliesToOpenBook(incomingBookID: bookID, currentBookID: book.id)
        else { return }   // stale report for a different book — ignore
        guard let locator = await locator(forSpine: spine, paragraph: para) else { return }
        // User took control on the X4: stop reading aloud and follow on screen.
        speech?.pause()
        jumpToken += 1
        pendingJump = JumpRequest(locator: locator, token: jumpToken)
        if let data = LocatorCoding.data(from: locator) {
            try? await readingState.updateLocator(bookID: book.id, locator: data)
            await syncEngine?.pushDirty()
        }
    }

    /// The phone's current reading position as the X4's `(spine, paragraph)` addressing,
    /// derived from the navigator's current locator. Sent to the X4 on connect
    /// (phone-wins). `nil` until a position is known.
    private func currentRemotePosition() async -> (spine: Int, para: Int)? {
        guard let locator = latestLocator, let spine = spineIndex(for: locator) else { return nil }
        let count = (try? await ReadiumStack.paragraphs(at: fileURL, spineIndex: spine).count) ?? 0
        let progression = locator.locations.progression ?? locator.locations.totalProgression ?? 0
        let para = RemotePositionMapping.paragraphOrdinal(progression: progression, paragraphCount: count)
        return (spine, para)
    }

    /// Approximate a Readium `Locator` for a `(spine, <p> ordinal)` position: the
    /// spine item's URL plus a progression from the paragraph's place in the chapter.
    private func locator(forSpine spine: Int, paragraph para: Int) async -> Locator? {
        guard let publication, publication.readingOrder.indices.contains(spine) else { return nil }
        let link = publication.readingOrder[spine]
        let count = (try? await ReadiumStack.paragraphs(at: fileURL, spineIndex: spine).count) ?? 0
        let progression = RemotePositionMapping.progression(paragraphOrdinal: para, paragraphCount: count)
        return Locator(
            href: link.url(),
            mediaType: link.mediaType ?? .html,
            locations: .init(progression: progression)
        )
    }

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

/// One row of the table of contents: a title at a nesting `depth`, the `Locator` to jump
/// to, and the spine index it lands in (for the current-section highlight).
struct TOCEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let depth: Int
    let locator: Locator?
    let spineIndex: Int?
}
