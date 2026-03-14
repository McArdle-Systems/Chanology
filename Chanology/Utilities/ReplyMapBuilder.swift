import Foundation

/// Builds a reverse reply map from thread posts.
///
/// Given an array of posts, scans each post's HTML comment for quotelink
/// `href="#pN"` references and builds a dictionary mapping each quoted post
/// number to the list of post numbers that quote it.
enum ReplyMapBuilder {

    /// Builds the reverse reply map: `targetPostNo → [replyingPostNo, ...]`
    static func build(from posts: [Post]) -> [Int: [Int]] {
        var map: [Int: [Int]] = [:]
        for post in posts {
            for quoted in quotedPosts(in: post) {
                map[quoted, default: []].append(post.no)
            }
        }
        return map
    }

    /// Returns the post numbers quoted by a given post.
    /// Deduplicates to ensure each post number appears only once.
    static func quotedPosts(in post: Post) -> [Int] {
        guard let com = post.com else { return [] }
        var results: Set<Int> = []
        // Match href="#pN" patterns from quotelinks
        let pattern = /href="#p(\d+)"/
        for match in com.matches(of: pattern) {
            if let postNo = Int(match.output.1) {
                results.insert(postNo)
            }
        }
        return Array(results).sorted()
    }
}
