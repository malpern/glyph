import Foundation

/// One `<p>` element from a spine item, named the way the X4 names it.
///
/// `ordinal` is the **1-based ordinal of the `<p>` start tag in document order**
/// within the spine item's raw HTML — the shared addressing key both devices agree
/// on (see the addressing contract). `text` is the decoded paragraph text (for
/// TTS), and `sentences` are its segments under the shared punctuation rule.
public struct Paragraph: Sendable, Equatable {
    /// 1-based `<p>` ordinal in document order (matches the X4's expat count).
    public let ordinal: Int
    /// Decoded, whitespace-collapsed paragraph text.
    public let text: String
    /// Sentence segments under the shared simple-punctuation rule (0-based ordinals).
    public let sentences: [String]

    public init(ordinal: Int, text: String, sentences: [String]) {
        self.ordinal = ordinal
        self.text = text
        self.sentences = sentences
    }
}
