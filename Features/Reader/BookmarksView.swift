import SwiftUI
import ReadiumShared
import ReaderCore

/// The bookmarks list for the open book: add the current page, tap to jump, swipe to
/// delete. Driven by `ReaderViewModel`, so jumps flow through the same navigator path.
struct BookmarksView: View {
    let viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark",
                        description: Text("Tap ➕ to bookmark the page you're on.")
                    )
                } else {
                    // Newest first.
                    ForEach(viewModel.bookmarks.reversed()) { bookmark in
                        Button {
                            viewModel.jump(to: bookmark)
                            dismiss()
                        } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add bookmark", systemImage: "plus") {
                        Task { await viewModel.addBookmark() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func delete(_ offsets: IndexSet) {
        let newestFirst = Array(viewModel.bookmarks.reversed())
        let ids = offsets.map { newestFirst[$0].id }
        Task { for id in ids { await viewModel.deleteBookmark(id) } }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark

    var body: some View {
        let locator = LocatorCoding.locator(from: bookmark.locator)
        VStack(alignment: .leading, spacing: 3) {
            Label(title(locator), systemImage: "bookmark.fill")
                .font(.body)
                .lineLimit(1)
            Text(subtitle(locator))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func title(_ locator: Locator?) -> String {
        let t = locator?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == false ? t : nil) ?? "Bookmark"
    }

    private func subtitle(_ locator: Locator?) -> String {
        let date = bookmark.createdAt.formatted(date: .abbreviated, time: .shortened)
        if let p = locator?.locations.totalProgression ?? locator?.locations.progression {
            return "\(Int((p * 100).rounded()))% · \(date)"
        }
        return date
    }
}
