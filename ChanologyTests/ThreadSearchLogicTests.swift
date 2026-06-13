import Testing
@testable import Chanology

// MARK: - Helper

/// Minimal Post factory — only the fields the search logic reads are interesting here.
private func post(
    no: Int,
    com: String? = nil,
    name: String? = nil,
    sub: String? = nil,
    filename: String? = nil,
    posterID: String? = nil
) -> Post {
    Post(
        no: no, now: "", name: name, trip: nil, posterID: posterID, capcode: nil,
        com: com, sub: sub, tim: nil, filename: filename, ext: nil, fsize: nil,
        w: nil, h: nil, tnW: nil, tnH: nil, md5: nil, mobileImg: nil, resto: 0,
        replies: nil, images: nil, sticky: nil, closed: nil, archived: nil,
        bumplimit: nil, imagelimit: nil, country: nil, countryName: nil,
        boardFlag: nil, flagName: nil
    )
}

/// Builds an `<a href="#pN" class="quotelink">` snippet — what real post HTML uses.
private func quote(_ n: Int) -> String {
    ##"<a href="#p\##(n)" class="quotelink">&gt;&gt;\##(n)</a>"##
}

// MARK: - Empty / no-match

@Test func matches_emptyQuery_returnsEmpty() {
    let posts = [post(no: 1, com: "hello")]
    #expect(ThreadSearchLogic.matches(query: "", posts: posts, myPostNumbers: []).isEmpty)
}

@Test func matches_noPosts_returnsEmpty() {
    #expect(ThreadSearchLogic.matches(query: "anything", posts: [], myPostNumbers: []).isEmpty)
}

@Test func matches_noMatch_returnsEmpty() {
    let posts = [post(no: 1, com: "hello world")]
    #expect(ThreadSearchLogic.matches(query: "zzz", posts: posts, myPostNumbers: []).isEmpty)
}

// MARK: - Standard text matching

@Test func matches_inComment() {
    let posts = [
        post(no: 1, com: "first post about swift"),
        post(no: 2, com: "second post about rust"),
    ]
    #expect(ThreadSearchLogic.matches(query: "swift", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_isCaseInsensitive() {
    let posts = [post(no: 1, com: "SwiftUI rocks")]
    #expect(ThreadSearchLogic.matches(query: "swiftui", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_inSubject() {
    let posts = [post(no: 1, sub: "Daily Coding Thread")]
    #expect(ThreadSearchLogic.matches(query: "daily", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_inName() {
    let posts = [post(no: 1, com: "x", name: "Moot")]
    #expect(ThreadSearchLogic.matches(query: "moot", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_inFilename() {
    let posts = [post(no: 1, com: "x", filename: "pepe_dance")]
    #expect(ThreadSearchLogic.matches(query: "pepe", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_inPosterID() {
    let posts = [post(no: 1, com: "x", posterID: "Xk9aB2")]
    #expect(ThreadSearchLogic.matches(query: "xk9", posts: posts, myPostNumbers: []) == [1])
}

@Test func matches_preservesPostOrder() {
    let posts = [
        post(no: 3, com: "match"),
        post(no: 1, com: "match"),
        post(no: 2, com: "nope"),
        post(no: 4, com: "match"),
    ]
    #expect(ThreadSearchLogic.matches(query: "match", posts: posts, myPostNumbers: []) == [3, 1, 4])
}

// MARK: - (You) marker matching

@Test func matches_youQuery_includesOwnPost() {
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: "my post"),
    ]
    #expect(ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [2]) == [2])
}

@Test func matches_youQuery_includesPostQuotingUser() {
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: "my own post"),
        post(no: 3, com: "\(quote(2)) replying to you"), // "you" literal also matches comment
        post(no: 4, com: "\(quote(2))"),                 // pure quote — only matches via (You) marker
    ]
    let matches = ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [2])
    #expect(matches == [2, 3, 4])
}

@Test func matches_youQuery_includesPostRepliedToByUser() {
    // Post 1 has no "(You)" anywhere in its own card UI EXCEPT the bottom reply pill,
    // which lists post 2 (the user's) replying to it.
    let posts = [
        post(no: 1, com: "OP — gets a reply from user"),
        post(no: 2, com: "\(quote(1)) my reply"),
        post(no: 3, com: "unrelated"),
    ]
    let matches = ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [2])
    #expect(matches == [1, 2])
}

@Test func matches_youQuery_multipleUserPostsQuotingSameTarget() {
    // Reply-pill match should still fire when several user posts quote the same target.
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: "\(quote(1)) my first reply"),
        post(no: 3, com: "\(quote(1)) my second reply"),
    ]
    let matches = ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [2, 3])
    #expect(matches == [1, 2, 3])
}

@Test func matches_youQuery_acceptsParensAndCasing() {
    let posts = [post(no: 7, com: "x")]
    let myPosts: Set<Int> = [7]
    #expect(ThreadSearchLogic.matches(query: "You", posts: posts, myPostNumbers: myPosts) == [7])
    #expect(ThreadSearchLogic.matches(query: "(You)", posts: posts, myPostNumbers: myPosts) == [7])
    #expect(ThreadSearchLogic.matches(query: "(you)", posts: posts, myPostNumbers: myPosts) == [7])
    #expect(ThreadSearchLogic.matches(query: " (You) ", posts: posts, myPostNumbers: myPosts) == [7])
}

@Test func matches_youQuery_noUserPosts_returnsEmpty() {
    let posts = [post(no: 1, com: "OP"), post(no: 2, com: "reply")]
    #expect(ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: []).isEmpty)
}

@Test func matches_youQuery_postsUnrelatedToUser_excluded() {
    let posts = [
        post(no: 1, com: "OP"),
        post(no: 2, com: "my post"),
        post(no: 3, com: "\(quote(1)) reply to OP, not to user"),
    ]
    // Only post 2 (the user's own) matches — post 3 quotes OP, not the user.
    #expect(ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [2]) == [2])
}

@Test func matches_youAsSubstring_doesNotTriggerMarker() {
    // "your" is a regular text query — should NOT light up (You) markers,
    // only text containing "your".
    let posts = [
        post(no: 1, com: "my own post"),       // user's own, but no "your" text
        post(no: 2, com: "your code is nice"), // contains "your"
    ]
    #expect(ThreadSearchLogic.matches(query: "your", posts: posts, myPostNumbers: [1]) == [2])
}

@Test func matches_youAsSubstring_inLongerQuery_doesNotTriggerMarker() {
    let posts = [
        post(no: 1, com: "my own post"),
        post(no: 2, com: "see you tomorrow"),
    ]
    // "see you" should be a literal text search, not a (You) marker search.
    #expect(ThreadSearchLogic.matches(query: "see you", posts: posts, myPostNumbers: [1]) == [2])
}

@Test func matches_shortQuery_doesNotTriggerMarker() {
    // "y" alone is too short — must not match every (You) marker as a side effect.
    // Note: post 1's comment is carefully chosen to NOT contain the letter 'y'.
    let posts = [
        post(no: 1, com: "the first one"),
        post(no: 2, com: "yellow"),
    ]
    #expect(ThreadSearchLogic.matches(query: "y", posts: posts, myPostNumbers: [1]) == [2])
}

@Test func matches_youQuery_dedupesWithTextMatch() {
    // A post that BOTH is the user's own AND contains "you" in its text
    // must appear only once in the results.
    let posts = [post(no: 5, com: "you should try this")]
    #expect(ThreadSearchLogic.matches(query: "you", posts: posts, myPostNumbers: [5]) == [5])
}
