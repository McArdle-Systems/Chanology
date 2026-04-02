import Foundation
import SwiftData

/// Tracks post numbers the user has made in a thread.
/// Decoupled from WatchedThread so (You) indicators work
/// regardless of watch state.
@Model
final class MyPosts {
    @Attribute(.unique) var threadKey: String   // "board/threadNo"
    var postNumbers: [Int] = []

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
