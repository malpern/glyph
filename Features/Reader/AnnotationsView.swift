import SwiftUI
import ReadiumShared
import ReaderCore

/// Bookmarks + highlights for the open book, in one sheet. Bookmarks are added here
/// (the current page); highlights are created by selecting text in the reader. Both
/// lists support tap-to-jump and swipe-to-delete, driven by `ReaderViewModel`.
struct AnnotationsView: View {
    let viewModel: ReaderViewModel
    var initialTab: Tab = .bookmarks
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .bookmarks

    enum Tab: String, CaseIterable { case bookmarks = "Bookmarks", highlights = "Highlights" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                switch tab {
                case .bookmarks: bookmarksList
                case .highlights: highlightsList
                }
            }
            .navigationTitle(tab.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { tab = initialTab }
            .toolbar {
                if tab == .bookmarks {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Add bookmark", systemImage: "plus") {
                            Task { await viewModel.addBookmark() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var bookmarksList: some View {
        List {
            if viewModel.bookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks", systemImage: "bookmark",
                    description: Text("Tap ➕ to bookmark the page you're on.")
                )
            } else {
                ForEach(viewModel.bookmarks.reversed()) { bookmark in
                    Button {
                        viewModel.jump(to: bookmark); dismiss()
                    } label: { BookmarkRow(bookmark: bookmark) }
                        .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    let newestFirst = Array(viewModel.bookmarks.reversed())
                    let ids = offsets.map { newestFirst[$0].id }
                    Task { for id in ids { await viewModel.deleteBookmark(id) } }
                }
            }
        }
    }

    @ViewBuilder private var highlightsList: some View {
        List {
            if viewModel.highlights.isEmpty {
                ContentUnavailableView(
                    "No Highlights", systemImage: "highlighter",
                    description: Text("Select text in the book, then tap Highlight.")
                )
            } else {
                ForEach(viewModel.highlights.reversed()) { highlight in
                    Button {
                        viewModel.jump(to: highlight); dismiss()
                    } label: { HighlightRow(highlight: highlight) }
                        .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    let newestFirst = Array(viewModel.highlights.reversed())
                    let ids = offsets.map { newestFirst[$0].id }
                    Task { for id in ids { await viewModel.deleteHighlight(id) } }
                }
            }
        }
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

private struct HighlightRow: View {
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(HighlightColor.from(highlight.color).uiColor))
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.text ?? "Highlight")
                    .font(.body)
                    .lineLimit(3)
                Text(highlight.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
