import Testing
import Foundation
@testable import Chanology

// MARK: - Helpers

private func makePost(no: Int, com: String? = nil) -> Post {
    Post(
        no: no, now: "", name: nil, trip: nil, posterID: nil, capcode: nil,
        com: com, sub: nil, tim: nil, filename: nil, ext: nil, fsize: nil,
        w: nil, h: nil, tnW: nil, tnH: nil, md5: nil, mobileImg: nil, resto: 99999,
        replies: nil, images: nil, sticky: nil, closed: nil, archived: nil,
        bumplimit: nil, imagelimit: nil, country: nil, countryName: nil,
        boardFlag: nil, flagName: nil
    )
}

private func quoteLink(_ postNo: Int, extra: String = "") -> String {
    let link = "<a href=\"#p\(postNo)\" class=\"quotelink\">&gt;&gt;\(postNo)</a>"
    return extra.isEmpty ? link : "\(link)<br>\(extra)"
}

private func build(posts: [Post], myPosts: Set<Int> = []) -> NotificationService.Payload {
    NotificationService.buildContent(board: "g", subject: "Test Thread", newPosts: posts, myPostNumbers: myPosts)
}

// MARK: - Title

@Test func notification_title_format() {
    let p = makePost(no: 1, com: "Hello")
    let payload = NotificationService.buildContent(board: "g", subject: "Tech", newPosts: [p], myPostNumbers: [])
    #expect(payload.title == "/g/ — Tech")
}

// MARK: - 1 direct reply

@Test func notification_1direct_showsReplyText() {
    let reply = makePost(no: 201, com: quoteLink(100, extra: "Nice post"))
    let payload = build(posts: [reply], myPosts: [100])
    #expect(payload.body.hasPrefix("@(You):"))
    #expect(payload.body.contains("Nice post"))
    #expect(payload.isDirectReply == true)
}

// MARK: - 2 direct replies

@Test func notification_2direct_showsCount() {
    let r1 = makePost(no: 201, com: quoteLink(100))
    let r2 = makePost(no: 202, com: quoteLink(100))
    let payload = build(posts: [r1, r2], myPosts: [100])
    #expect(payload.body == "2 replies to you")
    #expect(payload.isDirectReply == true)
}

// MARK: - 1 indirect reply

@Test func notification_1indirect_showsCommentText() {
    let p = makePost(no: 201, com: "Just a comment")
    let payload = build(posts: [p], myPosts: [100])
    #expect(payload.body == "Just a comment")
    #expect(payload.isDirectReply == false)
}

// MARK: - 2 indirect replies

@Test func notification_2indirect_showsNewRepliesCount() {
    let p1 = makePost(no: 201, com: "Comment A")
    let p2 = makePost(no: 202, com: "Comment B")
    let payload = build(posts: [p1, p2], myPosts: [100])
    #expect(payload.body == "2 new replies")
    #expect(payload.isDirectReply == false)
}

// MARK: - 1 direct + 1 indirect

@Test func notification_1direct_1indirect() {
    let direct = makePost(no: 201, com: quoteLink(100))
    let indirect = makePost(no: 202, com: "Other comment")
    let payload = build(posts: [direct, indirect], myPosts: [100])
    #expect(payload.body == "1 reply to you + 1 other")
    #expect(payload.isDirectReply == true)
}

// MARK: - 1 direct + 2 indirect

@Test func notification_1direct_2indirect() {
    let direct = makePost(no: 201, com: quoteLink(100))
    let i1 = makePost(no: 202, com: "A")
    let i2 = makePost(no: 203, com: "B")
    let payload = build(posts: [direct, i1, i2], myPosts: [100])
    #expect(payload.body == "1 reply to you + 2 others")
    #expect(payload.isDirectReply == true)
}

// MARK: - 2 direct + 1 indirect

@Test func notification_2direct_1indirect() {
    let d1 = makePost(no: 201, com: quoteLink(100))
    let d2 = makePost(no: 202, com: quoteLink(100))
    let indirect = makePost(no: 203, com: "Other")
    let payload = build(posts: [d1, d2, indirect], myPosts: [100])
    #expect(payload.body == "2 replies to you + 1 other")
    #expect(payload.isDirectReply == true)
}

// MARK: - 2 direct + 2 indirect

@Test func notification_2direct_2indirect() {
    let d1 = makePost(no: 201, com: quoteLink(100))
    let d2 = makePost(no: 202, com: quoteLink(100))
    let i1 = makePost(no: 203, com: "A")
    let i2 = makePost(no: 204, com: "B")
    let payload = build(posts: [d1, d2, i1, i2], myPosts: [100])
    #expect(payload.body == "2 replies to you + 2 others")
    #expect(payload.isDirectReply == true)
}

// MARK: - Empty myPostNumbers never produces a direct reply

@Test func notification_emptyMyPostNumbers_neverDirectReply() {
    let p = makePost(no: 201, com: quoteLink(100))
    let payload = build(posts: [p], myPosts: [])
    #expect(payload.isDirectReply == false)
}
