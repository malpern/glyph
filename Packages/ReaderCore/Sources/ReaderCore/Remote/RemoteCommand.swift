import Foundation

/// A command sent **phone → X4** over the remote-session WebSocket.
///
/// Modeled as a discriminated enum so new commands slot in without churning call
/// sites. Only `.ping` and `.goto` are LIVE on the device today; the rest are
/// designed per the protocol spec for when the firmware catches up. Encodes to the
/// compact JSON the device parses.
public enum RemoteCommand: Sendable, Equatable {
    /// `{"cmd":"ping"}` — liveness check. [LIVE]
    case ping
    /// `{"cmd":"goto","spine":S,"para":P}` — page-follow; `spine == -1` means
    /// "current spine". This is the live sync path. [LIVE]
    case goto(spine: Int, para: Int)
    /// `{"cmd":"open","bookId":"…"}` — announce/verify the loaded book. [PLANNED]
    case open(bookID: String)
    /// `{"cmd":"highlight","spine":S,"para":P,"sent":N,"text":?}` — highlight a
    /// position on the X4. With `sentence` set, it's a precise per-sentence highlight;
    /// with `sentence == nil` the `sent` key is omitted, which the firmware treats as
    /// a calm whole-**paragraph** mark (left-margin accent bar). [LIVE]
    case highlight(spine: Int, para: Int, sentence: Int?, text: String?)
    /// `{"cmd":"state","playing":B,"rate":R}` — mirror playback state. [PLANNED]
    case state(playing: Bool, rate: Double)
    /// `{"cmd":"count"}` — sentences on current page. [LIVE, TEST-ONLY]
    case count

    public func jsonData() -> Data {
        let object: [String: Any]
        switch self {
        case .ping:
            object = ["cmd": "ping"]
        case let .goto(spine, para):
            object = ["cmd": "goto", "spine": spine, "para": para]
        case let .open(bookID):
            object = ["cmd": "open", "bookId": bookID]
        case let .highlight(spine, para, sentence, text):
            var o: [String: Any] = ["cmd": "highlight", "spine": spine, "para": para]
            if let sentence { o["sent"] = sentence }   // omitted ⇒ paragraph mark
            if let text { o["text"] = text }
            object = o
        case let .state(playing, rate):
            object = ["cmd": "state", "playing": playing, "rate": rate]
        case .count:
            object = ["cmd": "count"]
        }
        return (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data("{}".utf8)
    }

    public func jsonString() -> String {
        String(decoding: jsonData(), as: UTF8.self)
    }
}
