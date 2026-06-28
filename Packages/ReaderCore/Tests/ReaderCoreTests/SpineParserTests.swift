import Testing
import Foundation
@testable import ReaderCore

/// Pins the addressing contract: `<p>` start tags only, 1-based, document order,
/// over raw bytes — matching the X4's expat count.
@Suite struct SpineParserTests {

    @Test func countsOnlyParagraphTagsNotDivHeadingOrLi() {
        let html = """
        <html><body>
          <h1>Chapter One</h1>
          <div>not a paragraph</div>
          <p>First.</p>
          <ul><li>not counted</li></ul>
          <p>Second.</p>
          <pre>also not a p</pre>
          <p>Third.</p>
        </body></html>
        """
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.count == 3)
        #expect(paras.map(\.ordinal) == [1, 2, 3])
        #expect(paras.map(\.text) == ["First.", "Second.", "Third."])
    }

    @Test func ordinalsAreOneBasedInDocumentOrder() {
        let html = "<p>a</p><p>b</p><p>c</p>"
        #expect(SpineParser.paragraphs(fromHTML: html).map(\.ordinal) == [1, 2, 3])
    }

    @Test func handlesAttributesSelfClosingAndStripsInlineTags() {
        let html = #"<p class="x">Hello <em>brave</em> world.</p><p/><p id="y">Done.</p>"#
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.count == 3)
        #expect(paras[0].text == "Hello brave world.")
        #expect(paras[1].text == "")           // empty <p/> still counts as ordinal 2
        #expect(paras[1].ordinal == 2)
        #expect(paras[2].text == "Done.")
    }

    @Test func decodesEntitiesAndCollapsesWhitespace() {
        let html = "<p>Tom &amp; Jerry  said\n  &ldquo;hi&rdquo; &#8212; really&#x21;</p>"
        let text = SpineParser.paragraphs(fromHTML: html).first?.text
        #expect(text == "Tom & Jerry said \u{201C}hi\u{201D} — really!")
    }

    @Test func doesNotCountParagraphTagsInsideComments() {
        let html = "<p>real</p><!-- <p>commented out</p> --><p>also real</p>"
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.count == 2)
        #expect(paras.map(\.text) == ["real", "also real"])
    }

    @Test func segmentsSentencesWithinParagraph() {
        let html = "<p>One sentence. A second one! And a third?</p>"
        let para = SpineParser.paragraphs(fromHTML: html).first
        #expect(para?.sentences == ["One sentence.", "A second one!", "And a third?"])
    }

    // MARK: - Contract edge cases (where ordinal drift would desync the X4 follow)

    @Test func doesNotCountParagraphTagsInsideCDATA() {
        let html = "<p>real</p><![CDATA[ <p>cdata</p> ]]><p>also real</p>"
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.map(\.text) == ["real", "also real"])
    }

    @Test func uppercaseParagraphTagsAreNotCounted() {
        // XHTML is case-sensitive; the X4's expat fires startElement only for lowercase <p>.
        let paras = SpineParser.paragraphs(fromHTML: "<P>shout</P><p>real</p>")
        #expect(paras.count == 1)
        #expect(paras.first?.text == "real")
    }

    @Test func tagsThatMerelyStartWithPAreNotParagraphs() {
        let html = "<pre>code</pre><picture></picture><param><p>only this</p>"
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.count == 1)
        #expect(paras.first?.text == "only this")
    }

    @Test func unclosedParagraphEndsWhereTheNextBegins() {
        let paras = SpineParser.paragraphs(fromHTML: "<p>one<p>two</p>")
        #expect(paras.map(\.ordinal) == [1, 2])
        #expect(paras.map(\.text) == ["one", "two"])
    }

    @Test func trailingUnclosedParagraphIsEmitted() {
        let paras = SpineParser.paragraphs(fromHTML: "<p>first</p><p>dangling")
        #expect(paras.map(\.text) == ["first", "dangling"])
    }

    @Test func strayCloseTagBeforeAnyOpenIsIgnored() {
        let paras = SpineParser.paragraphs(fromHTML: "</p><p>real</p>")
        #expect(paras.map(\.text) == ["real"])
    }

    @Test func selfClosingParagraphWithSpaceCountsAsEmpty() {
        let paras = SpineParser.paragraphs(fromHTML: "<p>a</p><p /><p>b</p>")
        #expect(paras.map(\.ordinal) == [1, 2, 3])
        #expect(paras.map(\.text) == ["a", "", "b"])
    }

    @Test func emptyAndParagraphlessInputYieldNoParagraphs() {
        #expect(SpineParser.paragraphs(fromHTML: "").isEmpty)
        #expect(SpineParser.paragraphs(fromHTML: "<body><div>nothing here</div></body>").isEmpty)
    }

    /// Golden: a realistic XHTML chapter exercising headings, divs, a comment, and
    /// numeric/named entities together — the ordinals must land 1..3 on the real `<p>`s.
    @Test func realisticChapterMapsOrdinalsToText() {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter 3</title></head>
        <body>
          <h2>The Meeting</h2>
          <p>It was a bright cold day in April.</p>
          <div class="ornament">* * *</div>
          <p class="indent">She said, &#8220;We&#8217;ll see&#8221; &mdash; and left.</p>
          <!-- editor note: <p>ignore me</p> -->
          <p>The&nbsp;end.</p>
        </body>
        </html>
        """
        let paras = SpineParser.paragraphs(fromHTML: html)
        #expect(paras.map(\.ordinal) == [1, 2, 3])
        #expect(paras.map(\.text) == [
            "It was a bright cold day in April.",
            "She said, \u{201C}We\u{2019}ll see\u{201D} — and left.",
            "The end.",
        ])
    }
}
