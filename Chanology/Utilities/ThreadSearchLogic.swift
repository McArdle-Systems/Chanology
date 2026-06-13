import Foundation

/// Pure search-matching logic for in-thread search.
///
/// Extracted from ThreadView so the logic can be unit tested without SwiftUI dependencies.
enum ThreadSearchLogic {

    /// Returns the post numbers that match `query`, preserving the order of `posts`.
    ///
    /// Matches against the post's plain-text comment, subject, name, filename, and poster ID.
    /// When `query` is the "(You)" marker (case-insensitive, optionally surrounded by parens
    /// or whitespace), also matches the three places "(You)" badges are rendered:
    ///   1. The post header — the post itself was authored by the user.
    ///   2. Inline quote tags in the body — the post quotes one of the user's posts.
    ///   3. Reply pills at the bottom — the post is replied to by one of the user's posts.
    static func matches(
        query: String,
        posts: [Post],
        myPostNumbers: Set<Int>
    ) -> [Int] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        let stripped = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        let matchesYouMarker = stripped == "you"

        let postsRepliedToByUser: Set<Int> = matchesYouMarker
            ? userReplyTargets(posts: posts, myPostNumbers: myPostNumbers)
            : []

        return posts.compactMap { post in
            let inComment  = post.plainTextComment?.lowercased().contains(lowered) == true
            let inSubject  = post.decodedSubject?.lowercased().contains(lowered) == true
            let inName     = post.name?.lowercased().contains(lowered) == true
            let inFilename = post.filename?.lowercased().contains(lowered) == true
            let inID       = post.posterID?.lowercased().contains(lowered) == true
            let inYouMarker = matchesYouMarker && postCarriesYouMarker(
                post,
                myPostNumbers: myPostNumbers,
                postsRepliedToByUser: postsRepliedToByUser
            )
            return (inComment || inSubject || inName || inFilename || inID || inYouMarker) ? post.no : nil
        }
    }

    /// Post numbers that are quoted by any of the user's own posts — i.e., the targets
    /// that will show a "(You)" reply pill at the bottom of their card.
    private static func userReplyTargets(posts: [Post], myPostNumbers: Set<Int>) -> Set<Int> {
        guard !myPostNumbers.isEmpty else { return [] }
        var targets: Set<Int> = []
        for post in posts where myPostNumbers.contains(post.no) {
            for quoted in ReplyMapBuilder.quotedPosts(in: post) {
                targets.insert(quoted)
            }
        }
        return targets
    }

    private static func postCarriesYouMarker(
        _ post: Post,
        myPostNumbers: Set<Int>,
        postsRepliedToByUser: Set<Int>
    ) -> Bool {
        guard !myPostNumbers.isEmpty else { return false }
        if myPostNumbers.contains(post.no) { return true }
        if postsRepliedToByUser.contains(post.no) { return true }
        return ReplyMapBuilder.quotedPosts(in: post).contains(where: myPostNumbers.contains)
    }
}
