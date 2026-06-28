import Testing
import Foundation
@testable import ReaderCore

@Suite struct InboxScannerTests {

    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/inbox/\($0)") }
    }

    @Test func picksEpubsCaseInsensitively() {
        let result = InboxScanner.epubsToIngest(in: urls(["a.epub", "b.EPUB", "c.Epub"]))
        #expect(result.map(\.lastPathComponent) == ["a.epub", "b.EPUB", "c.Epub"])
    }

    @Test func excludesNonEpubFiles() {
        let result = InboxScanner.epubsToIngest(in: urls(["doc.pdf", "notes.txt", "noext", "cover.jpg", "book.epub"]))
        #expect(result.map(\.lastPathComponent) == ["book.epub"])
    }

    /// AirDrop / USB copies drop a `._Foo.epub` AppleDouble stub next to `Foo.epub`;
    /// it has the .epub extension but isn't a real book, so it must be skipped.
    @Test func excludesAppleDoubleStubs() {
        let result = InboxScanner.epubsToIngest(in: urls(["._Moby.epub", "Moby.epub"]))
        #expect(result.map(\.lastPathComponent) == ["Moby.epub"])
    }

    @Test func returnsDeterministicNaturalOrder() {
        let result = InboxScanner.epubsToIngest(in: urls(["Book10.epub", "Book2.epub", "Book1.epub"]))
        #expect(result.map(\.lastPathComponent) == ["Book1.epub", "Book2.epub", "Book10.epub"])
    }

    @Test func emptyListingYieldsNothing() {
        #expect(InboxScanner.epubsToIngest(in: []).isEmpty)
    }
}
