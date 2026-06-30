import SwiftUI
import ReaderCore

/// Hosts a reading session: shows loading/error states, presents the EPUB
/// navigator when ready, and provides minimal auto-hiding chrome. Tapping the
/// center toggles the top bar; reading is otherwise distraction-free.
struct ReaderContainerView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
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
                .navigationTitle(viewModel.book.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "chevron.left") { close() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if !viewModel.tableOfContents.isEmpty {
                            Button { showingTOC = true } label: {
                                Image(systemName: "list.bullet")
                            }
                            .accessibilityLabel("Table of contents")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("Reading settings")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingBookmarks = true } label: {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Bookmarks")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let remote = viewModel.remoteSession {
                            Button {
                                remote.toggle()
                            } label: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(remoteTint(remote.connectionState, active: remote.isActive))
                            }
                            .accessibilityLabel(remote.isActive ? "Stop X4 session" : "Connect X4")
                        }
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
                onTap: { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } },
                onHighlightSelected: { locator in Task { await viewModel.createHighlight(at: locator) } },
                onHighlightTapped: { id in tappedHighlightID = UUID(uuidString: id) }
            )
            .ignoresSafeArea()
        }
    }

    private func remoteTint(_ state: X4Client.ConnectionState, active: Bool) -> Color {
        guard active else { return .secondary }
        switch state {
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
