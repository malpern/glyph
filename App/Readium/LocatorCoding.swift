import Foundation
import ReadiumShared

/// The single seam between Readium's `Locator` and the opaque `Data` that
/// `ReaderCore` stores. Keeping serialization here means `ReaderCore` never
/// imports Readium, and if the on-disk format ever needs to change it changes in
/// exactly one place.
///
/// Uses Readium's own deterministic JSON (sorted keys), so the bytes are stable
/// and comparable across devices — important for the future sync layer.
enum LocatorCoding {
    static func data(from locator: Locator) -> Data? {
        try? locator.jsonData()
    }

    static func locator(from data: Data) -> Locator? {
        try? Locator(jsonData: data)
    }
}
