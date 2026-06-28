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
}
