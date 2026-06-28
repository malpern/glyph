import Testing
@testable import ReaderCore

@Suite struct RemotePositionMappingTests {

    // MARK: - appliesToOpenBook

    @Test func untaggedRemotePositionIsTrusted() {
        #expect(RemotePositionMapping.appliesToOpenBook(incomingBookID: nil, currentBookID: "book-1"))
    }

    @Test func sameBookApplies() {
        #expect(RemotePositionMapping.appliesToOpenBook(incomingBookID: "book-1", currentBookID: "book-1"))
    }

    @Test func differentBookIsRejected() {
        #expect(RemotePositionMapping.appliesToOpenBook(incomingBookID: "book-2", currentBookID: "book-1") == false)
    }

    // MARK: - progression

    @Test func emptyOrSingleParagraphMapsToStart() {
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 1, paragraphCount: 0) == 0)
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 1, paragraphCount: 1) == 0)
    }

    @Test func firstParagraphIsStartOfItem() {
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 1, paragraphCount: 4) == 0)
    }

    @Test func interiorParagraphsAreEvenlySpaced() {
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 2, paragraphCount: 4) == 0.25)
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 3, paragraphCount: 4) == 0.5)
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 4, paragraphCount: 4) == 0.75)
    }

    @Test func ordinalBelowOneClampsToStart() {
        #expect(RemotePositionMapping.progression(paragraphOrdinal: 0, paragraphCount: 4) == 0)
        #expect(RemotePositionMapping.progression(paragraphOrdinal: -5, paragraphCount: 4) == 0)
    }

    /// The bug the inline version had: an ordinal past the end produced a progression
    /// ≥ 1 (an invalid Readium position). Clamping keeps it inside the item.
    @Test func ordinalPastEndClampsBelowOne() {
        let p = RemotePositionMapping.progression(paragraphOrdinal: 99, paragraphCount: 4)
        #expect(p == 0.75)
        #expect(p < 1.0)
    }

    @Test func progressionIsAlwaysInUnitRangeAndNonDecreasing() {
        let count = 10
        var previous = -1.0
        for ordinal in 0...(count + 3) {
            let p = RemotePositionMapping.progression(paragraphOrdinal: ordinal, paragraphCount: count)
            #expect(p >= 0 && p < 1.0)
            #expect(p >= previous)   // monotonic in ordinal
            previous = p
        }
    }
}
