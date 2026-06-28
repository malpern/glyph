import Foundation

/// Splits paragraph text into sentences using the **shared simple-punctuation
/// rule** the X4 implements (`hlEndsSentence`): a sentence ends on `.`, `!`, `?`,
/// or `…`, after peeling any trailing closing quotes/brackets.
///
/// This deliberately does NOT use `NLTokenizer` — its linguistically-aware
/// boundaries would not match the device's scanner, so a `sentenceOrdinal` would
/// mean different things on the two sides. Matching the device exactly (including
/// its "mistakes", e.g. splitting on "Mr.") is the whole point.
public enum SentenceSegmenter {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = [
        "\"", "'", "”", "’", "»", "›", ")", "]", "}",
    ]

    public static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if terminators.contains(c) {
                // Include any trailing closing quotes/brackets in this sentence.
                var j = i + 1
                while j < chars.count, closers.contains(chars[j]) {
                    current.append(chars[j])
                    j += 1
                }
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
                // Skip whitespace before the next sentence.
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                i = j
                continue
            }
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}
