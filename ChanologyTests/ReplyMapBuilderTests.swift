import Testing
@testable import Chanology

// MARK: - Helper

/// Minimal Post factory — only `no` and `com` matter for reply-map tests.
private func post(no: Int, com: String? = nil) -> Post {
    Post(
        no: no, now: "", name: nil, trip: nil, posterID: nil, capcode: nil,
        com: com, sub: nil, tim: nil, filename: nil, ext: nil, fsize: nil,
        w: nil, h: nil, tnW: nil, tnH: nil, md5: nil, resto: 0,
        replies: nil, images: nil, sticky: nil, closed: nil, archived: nil,
        bumplimit: nil, imagelimit: nil, country: nil, countryName: nil,
        boardFlag: nil, flagName: nil
    )
}

// MARK: - quotedPosts(in:)

@Test func quotedPosts_noComment_returnsEmpty() {
    let p = post(no: 1, com: nil)
    #expect(ReplyMapBuilder.quotedPosts(in: p).isEmpty)
}

@Test func quotedPosts_noQuoteLinks_returnsEmpty() {
    let p = post(no: 1, com: "Hello world, no links here")
    #expect(ReplyMapBuilder.quotedPosts(in: p).isEmpty)
}

@Test func quotedPosts_singleQuoteLink() {
    let p = post(no: 2, com: ##"<a href="#p100" class="quotelink">&gt;&gt;100</a>"##)
    #expect(ReplyMapBuilder.quotedPosts(in: p) == [100])
}

@Test func quotedPosts_multipleQuoteLinks_sorted() {
    let html = ##"<a href="#p300" class="quotelink">&gt;&gt;300</a> <a href="#p100" class="quotelink">&gt;&gt;100</a>"##
    let p = post(no: 2, com: html)
    #expect(ReplyMapBuilder.quotedPosts(in: p) == [100, 300])
}

@Test func quotedPosts_duplicateLinks_deduplicated() {
    let html = ##"<a href="#p100" class="quotelink">&gt;&gt;100</a> <a href="#p100" class="quotelink">&gt;&gt;100</a>"##
    let p = post(no: 2, com: html)
    #expect(ReplyMapBuilder.quotedPosts(in: p) == [100])
}

@Test func quotedPosts_ignoresCrossThreadLinks() {
    // Cross-thread links use /board/thread/N#pN — quotedPosts only matches href="#pN"
    let html = ##"<a href="/g/thread/12345#p100" class="quotelink">&gt;&gt;100</a>"##
    let p = post(no: 2, com: html)
    #expect(ReplyMapBuilder.quotedPosts(in: p).isEmpty)
}

// MARK: - build(from:)

@Test func build_emptyPosts_returnsEmptyMap() {
    let map = ReplyMapBuilder.build(from: [])
    #expect(map.isEmpty)
}

@Test func build_noQuotes_returnsEmptyMap() {
    let posts = [post(no: 1, com: "first"), post(no: 2, com: "second")]
    let map = ReplyMapBuilder.build(from: posts)
    #expect(map.isEmpty)
}

@Test func build_simpleReplyChain() {
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: ##"<a href="#p1" class="quotelink">&gt;&gt;1</a> reply to OP"##),
        post(no: 3, com: ##"<a href="#p1" class="quotelink">&gt;&gt;1</a> also replying to OP"##),
    ]
    let map = ReplyMapBuilder.build(from: posts)
    #expect(map[1] == [2, 3])
    #expect(map[2] == nil)
    #expect(map[3] == nil)
}

@Test func build_multipleTargets() {
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: "reply"),
        post(no: 3, com: ##"<a href="#p1" class="quotelink">&gt;&gt;1</a> <a href="#p2" class="quotelink">&gt;&gt;2</a>"##),
    ]
    let map = ReplyMapBuilder.build(from: posts)
    #expect(map[1] == [3])
    #expect(map[2] == [3])
}
