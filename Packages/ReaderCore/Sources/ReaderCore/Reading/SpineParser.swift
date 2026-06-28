import Foundation

/// Parses a spine item's **raw HTML bytes** into ordered `Paragraph`s, counting
/// `<p>` start tags exactly as the X4's expat parser does (`startElement("p")`):
/// case-sensitive lowercase `<p>` / `<p …>` / `<p/>`, in document order, 1-based.
/// Headings, `div`, and `li` are NOT counted — only `<p>`.
///
/// This is a lexical tag scan over the same bytes the X4 unzips, which is why the
/// ordinals agree without depending on two HTML engines normalizing identically.
/// It deliberately does not use Readium's `ContentElement` index (it includes
/// `div`/headings and normalizes), and stays dependency-free.
public enum SpineParser {
    /// Parse raw spine bytes (the result of `Resource.read()`).
    public static func paragraphs(fromHTML data: Data) -> [Paragraph] {
        paragraphs(fromHTML: String(decoding: data, as: UTF8.self))
    }

    public static func paragraphs(fromHTML html: String) -> [Paragraph] {
        let chars = Array(html)
        let n = chars.count
        var paragraphs: [Paragraph] = []
        var ordinal = 0
        var contentStart: Int? = nil      // index where the current <p>'s content begins
        var i = 0

        func matches(_ literal: [Character], at pos: Int) -> Bool {
            guard pos + literal.count <= n else { return false }
            for k in 0..<literal.count where chars[pos + k] != literal[k] { return false }
            return true
        }
        func emit(_ contentRange: Range<Int>) {
            paragraphs.append(Self.makeParagraph(ordinal: ordinal, rawContent: String(chars[contentRange])))
        }

        let commentOpen = Array("<!--"), commentClose = Array("-->")
        let cdataOpen = Array("<![CDATA["), cdataClose = Array("]]>")
        let pClose = Array("</p>")

        while i < n {
            // Skip comments and CDATA wholesale (their inner '<p' must not count).
            if matches(commentOpen, at: i) {
                var j = i + commentOpen.count
                while j < n, !matches(commentClose, at: j) { j += 1 }
                i = j < n ? j + commentClose.count : n
                continue
            }
            if matches(cdataOpen, at: i) {
                var j = i + cdataOpen.count
                while j < n, !matches(cdataClose, at: j) { j += 1 }
                i = j < n ? j + cdataClose.count : n
                continue
            }

            if chars[i] == "<" {
                // Close of the current paragraph.
                if contentStart != nil, matches(pClose, at: i) {
                    emit(contentStart!..<i)
                    contentStart = nil
                    i += pClose.count
                    continue
                }
                // Open <p> start tag: '<p' followed by whitespace, '/', or '>'.
                if i + 1 < n, chars[i + 1] == "p" {
                    let after = i + 2 < n ? chars[i + 2] : ">"
                    if after == ">" || after == "/" || after.isWhitespace {
                        // An unclosed previous <p> ends where this one begins.
                        if let start = contentStart { emit(start..<i); contentStart = nil }
                        ordinal += 1
                        var j = i + 2
                        while j < n, chars[j] != ">" { j += 1 }
                        let selfClosing = j > 0 && j <= n && chars[j - 1] == "/"
                        if selfClosing || j >= n {
                            emit(i..<i)                     // empty <p/>
                            i = j < n ? j + 1 : n
                        } else {
                            contentStart = j + 1
                            i = j + 1
                        }
                        continue
                    }
                }
            }
            i += 1
        }
        if let start = contentStart { emit(start..<n) }    // trailing unclosed <p>
        return paragraphs
    }

    // MARK: - Text extraction

    private static func makeParagraph(ordinal: Int, rawContent: String) -> Paragraph {
        let text = collapseWhitespace(decodeEntities(stripTags(rawContent)))
        return Paragraph(ordinal: ordinal, text: text, sentences: SentenceSegmenter.sentences(in: text))
    }

    private static func stripTags(_ s: String) -> String {
        var out = ""
        var inside = false
        for c in s {
            if c == "<" { inside = true }
            else if c == ">" { inside = false }
            else if !inside { out.append(c) }
        }
        return out
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "\u{2018}",
        "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "«", "raquo": "»",
    ]

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "&", let semi = chars[(i + 1)...].firstIndex(of: ";"), semi - i <= 12 {
                let body = String(chars[(i + 1)..<semi])
                if body.hasPrefix("#") {
                    let numStr = body.dropFirst()
                    let value: UInt32? = numStr.first == "x" || numStr.first == "X"
                        ? UInt32(numStr.dropFirst(), radix: 16)
                        : UInt32(numStr)
                    if let value, let scalar = Unicode.Scalar(value) {
                        out.unicodeScalars.append(scalar); i = semi + 1; continue
                    }
                } else if let replacement = namedEntities[body] {
                    out += replacement; i = semi + 1; continue
                }
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
