import Foundation

/// Plays one chunk of text (a sentence, in Glyph's case) through a TTS provider.
///
/// Glyph drives read-aloud one sentence at a time and syncs the X4 + on-screen
/// highlight at sentence granularity, so the engine contract is deliberately tiny:
/// speak a sentence, report when its audio actually **starts** (so the highlight lands
/// in sync with the voice) and when it **finishes** (so the controller advances). No
/// word-level timing is needed — that's the big simplification over VoxClaw, which
/// highlights word-by-word.
///
/// `onFinish` fires only on natural completion — never after `stop()` — so the
/// controller never double-advances when seeking or stopping.
@MainActor
protocol SpeechEngine: AnyObject {
    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void)
    func pause()
    func resume()
    func stop()
    /// Optionally warm the next sentence's audio while the current one plays (cloud
    /// engines override; on-device Apple ignores it).
    func prefetch(_ text: String, rate: Float)
}

extension SpeechEngine {
    func prefetch(_ text: String, rate: Float) {}
}
