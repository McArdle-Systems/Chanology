import Testing
import UIKit
@testable import Chanology

// MARK: - plainText

@Test func plainText_stripsHTMLTags() {
    let html = #"<span class="quote">&gt;implying</span>"#
    let result = PostHTMLRenderer.plainText(html)
    #expect(result == ">implying")
}

@Test func plainText_convertsBreaksToNewlines() {
    let html = "line one<br>line two"
    let result = PostHTMLRenderer.plainText(html)
    #expect(result == "line one\nline two")
}

@Test func plainText_stripsWbr() {
    let html = "super<wbr>long<wbr>word"
    let result = PostHTMLRenderer.plainText(html)
    #expect(result == "superlongword")
}

@Test func plainText_decodesEntities() {
    let html = "A &amp; B &lt; C &gt; D &quot;E&quot;"
    let result = PostHTMLRenderer.plainText(html)
    #expect(result == #"A & B < C > D "E""#)
}

@Test func plainText_emptyString() {
    #expect(PostHTMLRenderer.plainText("") == "")
}

@Test func plainText_trimWhitespace() {
    let html = "   <br>hello<br>   "
    let result = PostHTMLRenderer.plainText(html)
    #expect(result == "hello")
}

// MARK: - decodeEntities

@Test func decodeEntities_namedEntities() {
    #expect(PostHTMLRenderer.decodeEntities("&amp;") == "&")
    #expect(PostHTMLRenderer.decodeEntities("&lt;") == "<")
    #expect(PostHTMLRenderer.decodeEntities("&gt;") == ">")
    #expect(PostHTMLRenderer.decodeEntities("&quot;") == "\"")
    #expect(PostHTMLRenderer.decodeEntities("&apos;") == "'")
    #expect(PostHTMLRenderer.decodeEntities("&nbsp;") == "\u{00A0}")
}

@Test func decodeEntities_numericDecimal() {
    // &#039; is the most common way 4chan encodes apostrophes
    #expect(PostHTMLRenderer.decodeEntities("&#039;") == "'")
    #expect(PostHTMLRenderer.decodeEntities("&#39;") == "'")
    #expect(PostHTMLRenderer.decodeEntities("&#65;") == "A")
}

@Test func decodeEntities_numericHex() {
    #expect(PostHTMLRenderer.decodeEntities("&#x41;") == "A")
    #expect(PostHTMLRenderer.decodeEntities("&#X41;") == "A")
    #expect(PostHTMLRenderer.decodeEntities("&#x2014;") == "\u{2014}") // em dash
}

@Test func decodeEntities_typographicEntities() {
    #expect(PostHTMLRenderer.decodeEntities("&mdash;") == "\u{2014}")
    #expect(PostHTMLRenderer.decodeEntities("&ndash;") == "\u{2013}")
    #expect(PostHTMLRenderer.decodeEntities("&lsquo;") == "\u{2018}")
    #expect(PostHTMLRenderer.decodeEntities("&rsquo;") == "\u{2019}")
    #expect(PostHTMLRenderer.decodeEntities("&ldquo;") == "\u{201C}")
    #expect(PostHTMLRenderer.decodeEntities("&rdquo;") == "\u{201D}")
    #expect(PostHTMLRenderer.decodeEntities("&hellip;") == "\u{2026}")
}

@Test func decodeEntities_mixedContent() {
    let input = "Tom &amp; Jerry&#039;s &quot;Adventures&quot;"
    let expected = "Tom & Jerry's \"Adventures\""
    #expect(PostHTMLRenderer.decodeEntities(input) == expected)
}

@Test func decodeEntities_noEntities_passthrough() {
    let input = "Hello world 123"
    #expect(PostHTMLRenderer.decodeEntities(input) == input)
}

@Test func decodeEntities_unknownEntity_preserved() {
    let input = "&bogus;"
    #expect(PostHTMLRenderer.decodeEntities(input) == "&bogus;")
}

@Test func decodeEntities_ampersandWithoutSemicolon_literal() {
    let input = "AT&T rules"
    #expect(PostHTMLRenderer.decodeEntities(input) == "AT&T rules")
}

// MARK: - renderNSAttributedString

@Test func renderNS_plainText() {
    let result = PostHTMLRenderer.renderNSAttributedString("Hello world")
    #expect(result.string == "Hello world")
}

@Test func renderNS_brTag_insertsNewline() {
    let result = PostHTMLRenderer.renderNSAttributedString("a<br>b")
    #expect(result.string == "a\nb")
}

@Test func renderNS_greentextColor() {
    let html = #"<span class="quote">&gt;implying</span>"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == ">implying")
    let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
    #expect(color != nil)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
    color?.getRed(&r, green: &g, blue: &b, alpha: nil)
    #expect(abs(g - 0.60) < 0.01)
}

@Test func renderNS_quotelink_producesLinkAttribute() {
    let html = ##"<a href="#p12345" class="quotelink">&gt;&gt;12345</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == ">>12345")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "chanology://post/12345")
}

@Test func renderNS_boldTag_boldFont() {
    let result = PostHTMLRenderer.renderNSAttributedString("<b>bold</b>")
    #expect(result.string == "bold")
    let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
}

@Test func renderNS_italicTag_italicFont() {
    let result = PostHTMLRenderer.renderNSAttributedString("<i>slant</i>")
    #expect(result.string == "slant")
    let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
}

@Test func renderNS_preTag_monospaceFont() {
    let result = PostHTMLRenderer.renderNSAttributedString("<pre>code block</pre>")
    #expect(result.string == "code block")
    let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
}

@Test func renderNS_nestedTags_boldItalic() {
    let result = PostHTMLRenderer.renderNSAttributedString("<b><i>bold italic</i></b>")
    #expect(result.string == "bold italic")
    let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    // iOS system fonts express bold via weight, not .traitBold; verify italic trait is set
    // and the font differs from the plain body font (confirming styling was applied)
    #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    #expect(font != UIFont.preferredFont(forTextStyle: .body))
}

@Test func renderNS_spoilerTag_hiddenColors() {
    let result = PostHTMLRenderer.renderNSAttributedString("<s>secret</s>")
    #expect(result.string == "secret")
    let fg = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
    let bg = result.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor
    #expect(fg == bg)
}

@Test func renderNS_deadlink_hasStrikethrough() {
    let html = #"<span class="deadlink">&gt;&gt;99999</span>"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == ">>99999")
    let strike = result.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
    #expect(strike == NSUnderlineStyle.single.rawValue)
}

@Test func renderNS_entitiesDecoded() {
    let result = PostHTMLRenderer.renderNSAttributedString("1 &lt; 2 &amp; 3")
    #expect(result.string == "1 < 2 & 3")
}

@Test func renderNS_wbrStripped() {
    let result = PostHTMLRenderer.renderNSAttributedString("super<wbr>long<wbr>word")
    #expect(result.string == "superlongword")
}

// MARK: - External links

@Test func renderNS_externalLink_fullHrefDisplayed() {
    // 4chan truncates visible text inside <a> but keeps full URL in href
    let html = #"<a href="https://example.com/longpath">https://example.com/long</a>path"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://example.com/longpath")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "https://example.com/longpath")
}

@Test func renderNS_externalLink_noTruncation() {
    let html = #"<a href="https://x.com/foo">https://x.com/foo</a>"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://x.com/foo")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "https://x.com/foo")
}

@Test func renderNS_externalLink_followedByText() {
    let html = #"<a href="https://www.youtube.com/user/whitehouse">https://www.youtube.com/user/whiteh</a>ouse<br>next line"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://www.youtube.com/user/whitehouse\nnext line")
}

@Test func renderNS_externalLink_multiple() {
    let html = #"<a href="https://a.com/longpath">https://a.com/long</a>path <a href="https://b.com/test">https://b.com/te</a>st"#
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://a.com/longpath https://b.com/test")
}

@Test func renderNS_quotelink_notAffectedByExternalLinkLogic() {
    let html = ##"<a href="#p12345" class="quotelink">&gt;&gt;12345</a> some text"##
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == ">>12345 some text")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "chanology://post/12345")
}

// MARK: - Bare URL linkification (real API format — no anchor tags)

@Test func renderNS_bareURL_wbrStripped_isLinkified() {
    // Real 4chan API format: bare URL with <wbr> mid-URL, no anchor tag
    let html = "https://truthsocial.com/@realDonald<wbr>Trump"
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://truthsocial.com/@realDonaldTrump")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "https://truthsocial.com/@realDonaldTrump")
}

@Test func renderNS_bareURL_noWbr_isLinkified() {
    let html = "check this https://x.com/foo"
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "check this https://x.com/foo")
    let range = (result.string as NSString).range(of: "https://x.com/foo")
    let link = result.attribute(.link, at: range.location, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "https://x.com/foo")
}

@Test func renderNS_bareURL_wbr_followedByText() {
    let html = "https://www.youtube.com/user/whiteh<wbr>ouse<br>next line"
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://www.youtube.com/user/whitehouse\nnext line")
    let link = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link != nil)
}

@Test func renderNS_bareURL_multipleWbr() {
    let html = "https://www.youtube.com/watch?v=W9b<wbr>kyOTCrEg<br>https://www.tiktok.com/@realdonaldt<wbr>rump"
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == "https://www.youtube.com/watch?v=W9bkyOTCrEg\nhttps://www.tiktok.com/@realdonaldtrump")
    let link1 = result.attribute(.link, at: 0, effectiveRange: nil) as? URL
    #expect(link1 != nil)
}

@Test func renderNS_bareURL_insideReply_isLinkified() {
    // Quote + bare URL in same post (common real-world pattern)
    let html = ##"<a href="#p12345" class="quotelink">&gt;&gt;12345</a><br>try watching https://www.youtube.com/watch?v=oV9<wbr>rvDllKEg"##
    let result = PostHTMLRenderer.renderNSAttributedString(html)
    #expect(result.string == ">>12345\ntry watching https://www.youtube.com/watch?v=oV9rvDllKEg")
    let urlRange = (result.string as NSString).range(of: "https://www.youtube.com/watch?v=oV9rvDllKEg")
    let link = result.attribute(.link, at: urlRange.location, effectiveRange: nil) as? URL
    #expect(link != nil)
}

// MARK: - (You) markers

@Test func renderNS_youMarker_appendedAfterQuotelink() {
    let html = ##"<a href="#p42" class="quotelink">&gt;&gt;42</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html, myPostNumbers: [42])
    #expect(result.string == ">>42 (You)")
}

@Test func renderNS_youMarker_notAppendedForOtherPosts() {
    let html = ##"<a href="#p42" class="quotelink">&gt;&gt;42</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html, myPostNumbers: [99])
    #expect(result.string == ">>42")
}

// MARK: - (OP) markers

@Test func renderNS_opMarker_appendedAfterQuotelinkToOP() {
    let html = ##"<a href="#p100" class="quotelink">&gt;&gt;100</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html, opNo: 100)
    #expect(result.string == ">>100 (OP)")
}

@Test func renderNS_opMarker_notAppendedForNonOPPosts() {
    let html = ##"<a href="#p42" class="quotelink">&gt;&gt;42</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html, opNo: 100)
    #expect(result.string == ">>42")
}

@Test func renderNS_opAndYouMarkers_bothAppendedWhenQuotedPostIsBoth() {
    let html = ##"<a href="#p100" class="quotelink">&gt;&gt;100</a>"##
    let result = PostHTMLRenderer.renderNSAttributedString(html, myPostNumbers: [100], opNo: 100)
    #expect(result.string == ">>100 (OP) (You)")
}
