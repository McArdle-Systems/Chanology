import Foundation

/// Pure helpers for "replies to (You)" — shared by notifications, the poller, and the
/// catalog's replies-to-you counter.
enum ReplyTracking {
    /// Posts by others that quote at least one of the user's posts.
    /// The user's own posts are excluded, so quoting yourself doesn't count.
    static func directReplies(in posts: [Post], myPostNumbers: Set<Int>) -> [Post] {
        guard !myPostNumbers.isEmpty else { return [] }
        return posts.filter { post in
            !myPostNumbers.contains(post.no)
                && ReplyMapBuilder.quotedPosts(in: post).contains(where: myPostNumbers.contains)
        }
    }

    /// Title for a thread when no subject was stored: the OP's subject, else an excerpt.
    static func fallbackSubject(op: Post?) -> String {
        if let sub = op?.decodedSubject, !sub.isEmpty { return sub }
        if let text = op?.plainTextComment, !text.isEmpty { return String(text.prefix(60)) }
        return "Thread"
    }
}
