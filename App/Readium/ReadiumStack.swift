import Foundation
import UIKit
import ReadiumShared
import ReadiumStreamer
import ReaderCore

/// Reader-side error surface, kept deliberately small for Phase 1.
enum ReaderError: Error, LocalizedError {
    case unreadableFile
    case unsupportedPublication

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "This file could not be read."
        case .unsupportedPublication: return "This book format isn't supported."
        }
    }
}

/// A `Sendable` snapshot of everything import needs from a publication, so the
/// non-`Sendable` `Publication` never leaves this boundary.
struct PublicationMetadata: Sendable {
    let identifier: String?
    let title: String?
    let author: String?
    let coverPNG: Data?
}

/// The boundary that wires up Readium's parsing stack. This is the only place
/// that touches `Publication`: the reader gets a live `Publication` to render, and
/// import gets a `Sendable` `PublicationMetadata` snapshot. Keeping `Publication`
/// confined here means the rest of the app stays clean under complete strict
/// concurrency, and import can run off the main actor.
///
/// The components are cheap to build and opening is infrequent (import + each book
/// open), so a fresh stack is built per call — no shared mutable state.
enum ReadiumStack {
    /// Opens a publication for rendering in the navigator (reader path).
    static func open(at url: URL) async throws -> Publication {
        try await makePublication(at: url)
    }

    /// Opens a publication and extracts a `Sendable` snapshot (import path). The
    /// `Publication` stays local to this nonisolated function and is never returned.
    static func inspect(at url: URL) async throws -> PublicationMetadata {
        let publication = try await makePublication(at: url)
        // Read metadata first; the cover fetch is the last use of `publication`.
        let identifier = publication.metadata.identifier
        let title = publication.metadata.title
        let author = publication.metadata.authors.first?.name
        let coverPNG = ((try? await publication.cover().get()) ?? nil)?.pngData()
        return PublicationMetadata(identifier: identifier, title: title, author: author, coverPNG: coverPNG)
    }

    /// Number of spine items. Opens its own publication (nonisolated) and returns a
    /// plain `Int`, so the non-Sendable `Publication` never leaves this boundary.
    static func spineCount(at url: URL) async throws -> Int {
        try await makePublication(at: url).readingOrder.count
    }

    /// Parse a spine item into `Paragraph`s for TTS + X4 addressing. Reads the
    /// **raw, untransformed** bytes (the same bytes the X4 unzips) and counts `<p>`
    /// ordinals via `SpineParser`. Done entirely in this nonisolated function so the
    /// non-Sendable `Publication`/`Resource` never cross an isolation domain; only
    /// the `Sendable` `[Paragraph]` is returned.
    static func paragraphs(at url: URL, spineIndex: Int) async throws -> [Paragraph] {
        let publication = try await makePublication(at: url)
        guard publication.readingOrder.indices.contains(spineIndex) else {
            throw ReaderError.unsupportedPublication
        }
        guard let resource = publication.get(publication.readingOrder[spineIndex]) else {
            throw ReaderError.unreadableFile
        }
        let data = try await resource.read().get()
        return SpineParser.paragraphs(fromHTML: data)
    }

    /// Flatten the table of contents into Sendable, depth-tagged `TOCEntry`s — each with a
    /// `Locator` to jump to and the spine index it lands in (for the current-section
    /// highlight). Done in this nonisolated function so the non-Sendable `Publication`
    /// never crosses an isolation domain; only the `Sendable` `[TOCEntry]` is returned. A
    /// title-less node isn't shown but its children fold up to its own depth.
    static func tableOfContents(at url: URL) async throws -> [TOCEntry] {
        let publication = try await makePublication(at: url)
        let readingOrder = publication.readingOrder
        func spineIndex(for locator: Locator) -> Int? {
            readingOrder.firstIndex { locator.href.isEquivalentTo($0.url()) }
        }
        let links = (try? await publication.tableOfContents().get()) ?? []
        var entries: [TOCEntry] = []
        var stack = links.reversed().map { (link: $0, depth: 0) }
        while let (link, depth) = stack.popLast() {
            let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var childDepth = depth
            if !title.isEmpty {
                let locator = await publication.locate(link)
                entries.append(TOCEntry(
                    title: title, depth: depth,
                    locator: locator, spineIndex: locator.flatMap { spineIndex(for: $0) }
                ))
                childDepth = depth + 1
            }
            stack.append(contentsOf: link.children.reversed().map { (link: $0, depth: childDepth) })
        }
        // Fallback for books with no navigation document (e.g. some scanned/course EPUBs):
        // list the reading-order items so the reader can still jump between sections.
        if entries.isEmpty, readingOrder.count > 1 {
            for (index, link) in readingOrder.enumerated() {
                let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = (title?.isEmpty == false) ? title! : "Section \(index + 1)"
                let locator = await publication.locate(link)
                entries.append(TOCEntry(title: label, depth: 0, locator: locator, spineIndex: index))
            }
        }
        return entries
    }

    private static func makePublication(at url: URL) async throws -> Publication {
        let http = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: http)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: http,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        guard let fileURL = FileURL(url: url) else { throw ReaderError.unreadableFile }
        guard let asset = try? await assetRetriever.retrieve(url: fileURL).get() else {
            throw ReaderError.unreadableFile
        }
        guard let publication = try? await opener.open(asset: asset, allowUserInteraction: false).get() else {
            throw ReaderError.unsupportedPublication
        }
        return publication
    }
}
