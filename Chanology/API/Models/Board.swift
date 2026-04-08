import Foundation

struct Board: Codable, Identifiable, Hashable, Sendable {
    let board: String        // "g", "a", "b"
    let title: String        // "Technology"
    let wsBoard: Int         // 1 = work safe
    let perPage: Int
    let pages: Int
    let maxFilesize: Int
    let maxWebmFilesize: Int
    let maxCommentChars: Int
    let isArchived: Int?
    let boardFlags: [String: String]?

    var id: String { board }
    var isWorkSafe: Bool { wsBoard == 1 }
    var hasMemeFlags: Bool { !(boardFlags?.isEmpty ?? true) }

    enum CodingKeys: String, CodingKey {
        case board, title, pages
        case wsBoard = "ws_board"
        case perPage = "per_page"
        case maxFilesize = "max_filesize"
        case maxWebmFilesize = "max_webm_filesize"
        case maxCommentChars = "max_comment_chars"
        case isArchived = "is_archived"
        case boardFlags = "board_flags"
    }
}

struct BoardsResponse: Codable, Sendable {
    let boards: [Board]
}
