import Testing
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

// MARK: - render (AttributedString output)

@Test func render_plainText_noTags() {
    let result = PostHTMLRenderer.render("Hello world")
    #expect(String(result.characters) == "Hello world")
}

@Test func render_brTag_insertsNewline() {
    let result = PostHTMLRenderer.render("a<br>b")
    #expect(String(result.characters) == "a\nb")
}

@Test func render_greentextContent() {
    let html = #"<span class="quote">&gt;implying</span>"#
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == ">implying")
}

@Test func render_boldTag() {
    let html = "<b>bold text</b>"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "bold text")
}

@Test func render_italicTag() {
    let html = "<i>italic text</i>"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "italic text")
}

@Test func render_quotelink_producesLinkAttribute() {
    let html = ##"<a href="#p12345" class="quotelink">&gt;&gt;12345</a>"##
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == ">>12345")

    // Check that a link attribute is set on the rendered text
    var foundLink = false
    for run in result.runs {
        if run.link != nil {
            foundLink = true
            #expect(run.link?.absoluteString == "chanology://post/12345")
        }
    }
    #expect(foundLink)
}

@Test func render_deadlink_hasStrikethrough() {
    let html = #"<span class="deadlink">&gt;&gt;99999</span>"#
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == ">>99999")
}

@Test func render_spoilerTag_hiddenText() {
    let html = "<s>secret</s>"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "secret")
}

@Test func render_preTag_monospace() {
    let html = "<pre>code block</pre>"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "code block")
}

@Test func render_nestedTags() {
    let html = "<b><i>bold italic</i></b>"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "bold italic")
}

@Test func render_entitiesInText() {
    let html = "1 &lt; 2 &amp; 3 &gt; 0"
    let result = PostHTMLRenderer.render(html)
    #expect(String(result.characters) == "1 < 2 & 3 > 0")
}

// MARK: - External links

@Test func render_externalLink_fullHrefDisplayed() {
    // 4chan truncates the visible text inside <a> but keeps full URL in href
    let html = #"<a href="https://truthsocial.com/@realDonaldTrump">https://truthsocial.com/@realDonald</a>Trump"#
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    // Should show the full URL, not truncated + overflow
    #expect(text == "https://truthsocial.com/@realDonaldTrump")

    // Should be a tappable link
    var foundLink = false
    for run in result.runs {
        if let link = run.link {
            foundLink = true
            #expect(link.absoluteString == "https://truthsocial.com/@realDonaldTrump")
        }
    }
    #expect(foundLink)
}

@Test func render_externalLink_noTruncation_worksNormally() {
    // When 4chan doesn't truncate (short URL), it should still work
    let html = #"<a href="https://x.com/foo">https://x.com/foo</a>"#
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == "https://x.com/foo")
}

@Test func render_externalLink_followedByText() {
    // Truncated link with text after the overflow
    let html = #"<a href="https://www.youtube.com/user/whitehouse">https://www.youtube.com/user/whiteh</a>ouse<br>next line"#
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == "https://www.youtube.com/user/whitehouse\nnext line")
}

@Test func render_externalLink_multipleOnSameLine() {
    let html = #"<a href="https://a.com/longpath">https://a.com/long</a>path <a href="https://b.com/test">https://b.com/te</a>st"#
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == "https://a.com/longpath https://b.com/test")
}

@Test func render_quotelink_notAffectedByExternalLinkLogic() {
    // Quotelinks should still work normally
    let html = ##"<a href="#p12345" class="quotelink">&gt;&gt;12345</a> some text"##
    let result = PostHTMLRenderer.render(html)
    let text = String(result.characters)
    #expect(text == ">>12345 some text")
}
