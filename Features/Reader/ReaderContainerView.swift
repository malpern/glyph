import SwiftUI
import ReaderCore

/// Hosts a reading session: shows loading/error states, presents the EPUB
/// navigator when ready, and provides minimal auto-hiding chrome. Tapping the
/// center toggles the top bar; reading is otherwise distraction-free.
struct ReaderContainerView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showChrome = true
    @State private var showingSettings = false
    @State private var showingBookmarks = false
    @State private var showingTOC = false
    @State private var annotationsTab: AnnotationsView.Tab = .bookmarks
    @State private var tappedHighlightID: UUID?

    init(
        book: Book,
        fileURL: URL,
        readingState: any ReadingStateRepository,
        syncEngine: ReadingStateSyncEngine?
    ) {
        _viewModel = State(initialValue: ReaderViewModel(
            book: book, fileURL: fileURL, readingState: readingState, syncEngine: syncEngine
        ))
    }

    var body: some View {
        NavigationStack {
            content
                // No inline title: a single immersive reading view doesn't need the book
                // title permanently in the bar, and dropping it reclaims the width the
                // controls were colliding over.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "chevron.left") { close() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingTOC = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Table of contents")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let speech = viewModel.speech {
                            Button {
                                Task { await viewModel.toggleSpeech() }
                            } label: {
                                Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .accessibilityLabel(speech.isPlaying ? "Pause read-aloud" : "Read aloud")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showingSettings = true } label: {
                                Label("Reading Settings", systemImage: "textformat.size")
                            }
                            Button { showingBookmarks = true } label: {
                                Label("Bookmarks & Highlights", systemImage: "bookmark")
                            }
                            if let remote = viewModel.remoteSession {
                                Button { remote.toggle() } label: {
                                    Label(remote.isActive ? "Stop X4 Session" : "Connect X4",
                                          systemImage: "dot.radiowaves.left.and.right")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        // Tint the overflow when an X4 session is live, so its connection
                        // state stays glanceable without a dedicated toolbar button.
                        .tint(remoteMenuTint)
                        .accessibilityLabel("More")
                    }
                }
                // Native Liquid Glass nav bar that auto-hides for distraction-free
                // reading; tapping the page toggles it.
                .toolbarVisibility(showChrome ? .visible : .hidden, for: .navigationBar)
                .statusBarHidden(!showChrome)
                .sheet(isPresented: $showingSettings) {
                    ReaderSettingsView(store: container.readerSettings)
                }
                .sheet(isPresented: $showingBookmarks) {
                    AnnotationsView(viewModel: viewModel, initialTab: annotationsTab)
                }
                .sheet(isPresented: $showingTOC) {
                    TableOfContentsView(
                        entries: viewModel.tableOfContents,
                        currentID: viewModel.currentTOCID,
                        onSelect: { viewModel.jump(toTOC: $0) }
                    )
                }
                .confirmationDialog(
                    "Highlight",
                    isPresented: Binding(
                        get: { tappedHighlightID != nil },
                        set: { if !$0 { tappedHighlightID = nil } }
                    ),
                    presenting: tappedHighlightID
                ) { id in
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button(color.label) {
                            Task { await viewModel.recolorHighlight(id, to: color) }
                        }
                    }
                    Button("Delete Highlight", role: .destructive) {
                        Task { await viewModel.deleteHighlight(id) }
                    }
                }
        }
        .task {
            viewModel.attach(settings: container.readerSettings)
            await viewModel.load()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["READER_AUTOREMOTE"] == "1" { viewModel.remoteSession?.start() }
            if env["READER_AUTOSPEAK"] == "1" { await viewModel.toggleSpeech() }
            if env["READER_AUTOBOOKMARK"] == "1" {
                try? await Task.sleep(for: .seconds(3))   // let the first locationDidChange land
                await viewModel.addBookmark()
                showingBookmarks = true
            }
            if let text = env["READER_AUTOHIGHLIGHT"] {
                try? await Task.sleep(for: .seconds(4))    // settle on a text page first
                await viewModel.debugCreateHighlight(text: text)
                annotationsTab = .highlights
                showingBookmarks = true
            }
            #endif
        }
        .onChange(of: ttsSignature) { _, _ in viewModel.rebuildSpeechEngine() }
        .onChange(of: scenePhase) { _, phase in
            // Suspend the X4 socket in the background (read-aloud audio keeps playing);
            // reconnect on return to foreground.
            switch phase {
            case .background: viewModel.remoteSession?.suspend()
            case .active: viewModel.remoteSession?.resume()
            default: break
            }
        }
    }

    /// Changes when the user picks a different TTS provider or voice — triggers a live
    /// engine rebuild so the new voice applies without reopening the book.
    private var ttsSignature: String {
        let s = container.readerSettings.settings
        return "\(s.ttsProvider.rawValue)|\(s.openAIVoice)|\(s.elevenLabsVoiceID)"
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .failed(message):
            VStack(spacing: 16) {
                ContentUnavailableView("Couldn't Open Book", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Close") { dismiss() }
            }
        case let .ready(publication, initialLocator):
            let tts = viewModel.ttsLocators
            EPUBReaderView(
                publication: publication,
                initialLocator: initialLocator,
                preferences: container.readerSettings.epubPreferences,
                pendingJump: viewModel.pendingJump,
                ttsHighlight: tts.highlight,
                ttsFollow: tts.follow,
                highlights: viewModel.highlightDecorations,
                onLocationChange: { viewModel.locationChanged($0) },
                onTap: { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showChrome.toggle() } },
                onHighlightSelected: { locator in Task { await viewModel.createHighlight(at: locator) } },
                onHighlightTapped: { id in tappedHighlightID = UUID(uuidString: id) }
            )
            .ignoresSafeArea()
        }
    }

    /// Overflow-menu tint reflecting the X4 connection state while a session is active,
    /// or `nil` (default glass tint) when no session is running.
    private var remoteMenuTint: Color? {
        guard let remote = viewModel.remoteSession, remote.isActive else { return nil }
        switch remote.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private func close() {
        Task {
            viewModel.stopAll()       // stop speech + disconnect X4
            await viewModel.flush()   // make resume exact before tearing down
            dismiss()
        }
    }
}
