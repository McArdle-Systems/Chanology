import Foundation

/// Builds a display title for a freshly-created thread from the user-typed
/// subject and comment, falling back to `Thread #N` when both are empty.
enum NewThreadTitleBuilder {
    /// Max length of the comment-derived fallback before it's truncated with `…`.
    static let maxCommentTitleLength = 80

    static func title(subject: String, comment: String, threadNo: Int) -> String {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSubject.isEmpty { return trimmedSubject }

        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            let firstLine = trimmedComment
                .split(whereSeparator: { $0.isNewline })
                .first
                .map(String.init) ?? trimmedComment
            if firstLine.count > maxCommentTitleLength {
                return String(firstLine.prefix(maxCommentTitleLength)) + "…"
            }
            return firstLine
        }

        return "Thread #\(threadNo)"
    }
}
