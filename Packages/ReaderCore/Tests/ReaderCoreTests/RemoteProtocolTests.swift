import Testing
import Foundation
@testable import ReaderCore

@Suite struct RemoteProtocolTests {

    // MARK: Commands (phone -> X4)

    @Test func encodesPingAndGoto() {
        #expect(RemoteCommand.ping.jsonString() == #"{"cmd":"ping"}"#)
        #expect(RemoteCommand.goto(spine: 4, para: 12).jsonString() == #"{"cmd":"goto","para":12,"spine":4}"#)
    }

    @Test func encodesGotoCurrentSpine() {
        #expect(RemoteCommand.goto(spine: -1, para: 3).jsonString() == #"{"cmd":"goto","para":3,"spine":-1}"#)
    }

    @Test func encodesHighlightWithAndWithoutText() {
        #expect(RemoteCommand.highlight(spine: 4, para: 12, sentence: 2, text: nil).jsonString()
            == #"{"cmd":"highlight","para":12,"sent":2,"spine":4}"#)
        let withText = RemoteCommand.highlight(spine: 4, para: 12, sentence: 2, text: "It was a bright cold day").jsonString()
        #expect(withText.contains(#""cmd":"highlight""#))
        #expect(withText.contains(#""text":"It was a bright cold day""#))
    }

    @Test func encodesOpenWithUnescapedSlashes() {
        // bookId is often a URL-like dc:identifier; slashes should not be escaped.
        #expect(RemoteCommand.open(bookID: "http://www.gutenberg.org/11").jsonString()
            == #"{"bookId":"http://www.gutenberg.org/11","cmd":"open"}"#)
    }

    // MARK: Events (X4 -> phone)

    @Test func decodesLiveEvents() {
        #expect(RemoteEvent.decode(#"{"evt":"ready"}"#) == .ready(spine: nil, para: nil, bookID: nil))
        #expect(RemoteEvent.decode(#"{"evt":"pong"}"#) == .pong)
        #expect(RemoteEvent.decode(#"{"evt":"goto","spine":4,"para":12,"ok":true}"#)
            == .gotoAck(spine: 4, para: 12, ok: true))
    }

    @Test func decodesReadyWithPositionAndBookId() {
        #expect(RemoteEvent.decode(#"{"evt":"ready","spine":4,"para":12,"bookId":"urn:x"}"#)
            == .ready(spine: 4, para: 12, bookID: "urn:x"))
        // back-compat: an older firmware sending "page" maps to para
        #expect(RemoteEvent.decode(#"{"evt":"ready","spine":4,"page":37}"#)
            == .ready(spine: 4, para: 37, bookID: nil))
    }

    @Test func decodesPositionAndButton() {
        #expect(RemoteEvent.decode(#"{"evt":"pos","spine":4,"para":12}"#) == .position(spine: 4, para: 12))
        #expect(RemoteEvent.decode(#"{"evt":"button","action":"play"}"#) == .button(action: "play"))
    }

    @Test func toleratesUnknownEventsAndExtraFields() {
        #expect(RemoteEvent.decode(#"{"evt":"something_new","x":1}"#) == .unknown(type: "something_new"))
        // extra/unexpected fields on a known event are ignored
        #expect(RemoteEvent.decode(#"{"evt":"pong","extra":99,"more":"x"}"#) == .pong)
        // malformed / non-event JSON returns nil
        #expect(RemoteEvent.decode(#"{"no_evt":true}"#) == nil)
        #expect(RemoteEvent.decode("not json") == nil)
    }
}
