import Foundation
import SwiftData

/// Tracks post numbers the user has made in a thread.
/// Decoupled from WatchedThread so (You) indicators work
/// regardless of watch state.
///
/// Threads with a MyPosts record are also polled (see `ThreadPoller`) so the user is
/// notified of direct replies even when they aren't watching the thread.
@Model
final class MyPosts {
    @Attribute(.unique) var threadKey: String   // "board/threadNo"
    var postNumbers: [Int] = []

    // Polling state. All have defaults so existing stores migrate automatically.

    /// Thread subject (or OP excerpt) for notification titles.
    var subject: String = ""
    /// Highest post number the poller has processed. 0 = never polled: the first poll
    /// records a baseline without notifying, so old replies don't fire on upgrade.
    var lastSeenPostNo: Int = 0
    /// Number of posts in the thread (by others) that quote one of the user's posts.
    var directReplyCount: Int = 0
    var isArchived: Bool = false
    /// The thread 404'd (pruned). Kept so (You) markers survive, but never polled again.
    var isGone: Bool = false

    var shouldPoll: Bool { !isArchived && !isGone && !postNumbers.isEmpty }

    var board: String { String(threadKey.split(separator: "/").first ?? "") }
    var threadNo: Int { Int(threadKey.split(separator: "/").last ?? "") ?? 0 }

    init(board: String, threadNo: Int) {
        self.threadKey = "\(board)/\(threadNo)"
    }

    /// Convenience to add a post number if not already tracked.
    func addPost(_ postNo: Int) {
        guard !postNumbers.contains(postNo) else { return }
        postNumbers.append(postNo)
    }

    static func key(board: String, threadNo: Int) -> String {
        "\(board)/\(threadNo)"
    }
}
