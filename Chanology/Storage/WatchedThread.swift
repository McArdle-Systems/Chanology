import Foundation
import SwiftData

@Model
final class WatchedThread {
    var board: String
    var threadNo: Int
    var subject: String
    var lastSeenPostNo: Int
    /// The last post the user actually read (scrolled past). Used to show "New Replies" marker.
    var lastReadPostNo: Int = 0
    var newReplyCount: Int
    var lastChecked: Date
    /// Post numbers the user has made in this thread (for reply highlighting).
    var myPostNumbers: [Int] = []

    init(board: String, threadNo: Int, subject: String, lastSeenPostNo: Int) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        self.lastSeenPostNo = lastSeenPostNo
        self.lastReadPostNo = lastSeenPostNo
        self.newReplyCount = 0
        self.lastChecked = Date()
    }
}

extension WatchedThread: Hashable {
    static func == (lhs: WatchedThread, rhs: WatchedThread) -> Bool {
        lhs.board == rhs.board && lhs.threadNo == rhs.threadNo
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(board)
        hasher.combine(threadNo)
    }
}
