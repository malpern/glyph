import Foundation

/// Pure mapping helpers for turning an X4 e-ink `(spine, paragraph)` report into a
/// position this phone can store and sync. Kept here — UI-free and Readium-free — so
/// the desync-prone math is exercised by the fast unit suite instead of being trapped
/// behind the reader's Readium/AVFoundation stack.
public enum RemotePositionMapping {

    /// Whether a remote position tagged with `incomingBookID` should be adopted while
    /// the reader is showing `currentBookID`.
    ///
    /// A `nil` id means the source didn't say which book it was — we trust it, since
    /// the X4 mirrors whatever the phone opened. A present-but-different id is a stale
    /// report for another book and is rejected.
    public static func appliesToOpenBook(incomingBookID: String?, currentBookID: String) -> Bool {
        guard let incomingBookID else { return true }
        return incomingBookID == currentBookID
    }

    /// Map a 1-based paragraph ordinal within a spine item of `paragraphCount`
    /// paragraphs to a Readium-style reading progression in `[0, 1)`.
    ///
    /// Mirrors the addressing `SpineParser` emits — 1-based ordinals matching the X4
    /// firmware's expat paragraph count — so the phone resumes on exactly the unit the
    /// e-ink device reported. A count of 0 or 1 has no meaningful sub-position, so it
    /// maps to the start of the item. Out-of-range ordinals are clamped into the item
    /// rather than allowed to produce a progression ≥ 1.
    public static func progression(paragraphOrdinal ordinal: Int, paragraphCount count: Int) -> Double {
        guard count > 1 else { return 0 }
        let zeroBased = max(0, ordinal - 1)
        let clamped = min(zeroBased, count - 1)
        return Double(clamped) / Double(count)
    }

    /// Inverse of `progression(paragraphOrdinal:paragraphCount:)`: map a Readium reading
    /// progression in `[0, 1]` to the 1-based paragraph ordinal it falls within. Used to
    /// report the phone's current position to the X4 (`goto` on connect). Round-trips with
    /// `progression(...)` for in-range ordinals; for a continuous progression it returns
    /// the paragraph containing it.
    public static func paragraphOrdinal(progression: Double, paragraphCount count: Int) -> Int {
        guard count > 1 else { return 1 }
        let clamped = min(max(progression, 0), 1)
        let zeroBased = min(Int(clamped * Double(count)), count - 1)   // floor, matching the forward map
        return zeroBased + 1
    }
}
