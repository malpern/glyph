import SwiftUI
import UniformTypeIdentifiers
import ReaderCore

/// The library grid — the app's home. Deliberately quiet: covers on a plain
/// background, a single "+" to add books, nothing else competing for attention.
struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @Environment(AppContainer.self) private var container

    @State private var showingFileImporter = false
    @State private var showingSync = false
    @State private var openedBook: Book?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 24, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.books.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSync = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Sync settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import book")
                }
            }
            .sheet(isPresented: $showingSync) { SyncSettingsView() }
            .fullScreenCover(item: $openedBook) { book in
                ReaderContainerView(
                    book: book,
                    fileURL: container.storage.absoluteURL(for: book.filePath),
                    readingState: container.readingState,
                    syncEngine: container.syncEngine
                )
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task { await viewModel.importBook(from: url) }
                }
            }
            .overlay { if viewModel.isImporting { ProgressView().controlSize(.large) } }
            .task {
                await viewModel.load()
                await runAutoDemoIfRequested()
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(viewModel.books) { book in
                    Button {
                        openedBook = book
                    } label: {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(book) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// DEBUG-only hook so headless simulator runs can populate the library and
    /// open a book for screenshots/automated checks. Never compiled into release.
    private func runAutoDemoIfRequested() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["READER_AUTODEMO"] == "1" else { return }
        if viewModel.books.isEmpty { await viewModel.importSample() }
        if env["READER_AUTOOPEN"] == "1" { openedBook = viewModel.books.first }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Image("BookArtwork")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(spacing: 6) {
                Text("No Books")
                    .font(.title2.weight(.semibold))
                Text("Import an EPUB to start reading.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button("Import a Book…") { showingFileImporter = true }
                    .buttonStyle(.borderedProminent)
                Button("Add Sample Book") { Task { await viewModel.importSample() } }
            }
        }
        .padding()
    }
}
