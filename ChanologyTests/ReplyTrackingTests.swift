import Testing
import Foundation
@testable import Chanology

private func makePost(no: Int, com: String? = nil, sub: String? = nil) -> Post {
    Post(
        no: no, now: "", name: nil, trip: nil, posterID: nil, capcode: nil,
        com: com, sub: sub, tim: nil, filename: nil, ext: nil, fsize: nil,
        w: nil, h: nil, tnW: nil, tnH: nil, md5: nil, mobileImg: nil, resto: 0,
        replies: nil, images: nil, sticky: nil, closed: nil, archived: nil,
        bumplimit: nil, imagelimit: nil, country: nil, countryName: nil,
        boardFlag: nil, flagName: nil
    )
}

private func quote(_ no: Int) -> String {
    "<a href=\"#p\(no)\" class=\"quotelink\">&gt;&gt;\(no)</a>"
}

@Test func directReplies_countsPostsQuotingMine() {
    let posts = [
        makePost(no: 100, com: "mine"),
        makePost(no: 101, com: quote(100)),
        makePost(no: 102, com: "unrelated"),
        makePost(no: 103, com: quote(100) + "<br>" + quote(102)),
    ]
    let replies = ReplyTracking.directReplies(in: posts, myPostNumbers: [100])
    #expect(replies.map(\.no) == [101, 103])
}

@Test func directReplies_excludesSelfQuotes() {
    let posts = [
        makePost(no: 100, com: "mine"),
        makePost(no: 101, com: quote(100)), // also mine
    ]
    #expect(ReplyTracking.directReplies(in: posts, myPostNumbers: [100, 101]).isEmpty)
}

@Test func directReplies_countsEachPostOnceAcrossMultipleOfMine() {
    let posts = [makePost(no: 300, com: quote(100) + "<br>" + quote(200))]
    #expect(ReplyTracking.directReplies(in: posts, myPostNumbers: [100, 200]).count == 1)
}

@Test func directReplies_emptyWithoutMyPosts() {
    let posts = [makePost(no: 101, com: quote(100))]
    #expect(ReplyTracking.directReplies(in: posts, myPostNumbers: []).isEmpty)
}

@Test func fallbackSubject_prefersSubjectThenExcerpt() {
    #expect(ReplyTracking.fallbackSubject(op: makePost(no: 1, com: "body", sub: "Title")) == "Title")
    #expect(ReplyTracking.fallbackSubject(op: makePost(no: 1, com: "just a body")) == "just a body")
    #expect(ReplyTracking.fallbackSubject(op: nil) == "Thread")
}

@Test func myPosts_parsesKeyAndGatesPolling() {
    let record = MyPosts(board: "vg", threadNo: 4242)
    #expect(record.board == "vg")
    #expect(record.threadNo == 4242)
    #expect(!record.shouldPoll) // no posts yet
    record.addPost(4250)
    #expect(record.shouldPoll)
    record.isArchived = true
    #expect(!record.shouldPoll)
    record.isArchived = false
    record.isGone = true
    #expect(!record.shouldPoll)
}
