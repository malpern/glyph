import Foundation
import ReadiumShared
import ReadiumStreamer

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

/// The boundary that turns a file URL into a Readium `Publication`. This is the
/// only place that wires up Readium's parsing stack; the rest of the app receives
/// a ready `Publication` (for the reader) or extracted metadata (for import).
///
/// The components are cheap to construct and opening is infrequent (import + each
/// book open), so a fresh stack is built per call — this sidesteps shared-state
/// concurrency concerns entirely.
enum ReadiumStack {
    static func open(at url: URL) async throws -> Publication {
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
