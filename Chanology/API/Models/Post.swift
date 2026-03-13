import Foundation

/// A single post within a thread (from the thread endpoint)
struct Post: Codable, Identifiable, Sendable {
    let no: Int              // Post number (unique ID)
    let now: String          // Date string "MM/DD/YY(Day)HH:MM:SS"
    let name: String?        // Poster name
    let trip: String?        // Tripcode
    let id: String?          // Poster ID (on boards that show it)
    let capcode: String?     // mod/admin capcode
    let com: String?         // Comment HTML
    let sub: String?         // Subject (OP only)
    let tim: Int?            // Image timestamp (filename on CDN)
    let filename: String?    // Original filename
    let ext: String?         // File extension
    let fsize: Int?          // File size in bytes
    let w: Int?              // Image width
    let h: Int?              // Image height
    let tnW: Int?            // Thumbnail width
    let tnH: Int?            // Thumbnail height
    let md5: String?         // Image MD5
    let resto: Int           // 0 if OP, else thread number this replies to
    let replies: Int?        // Reply count (OP only)
    let images: Int?         // Image count (OP only)
    let sticky: Int?
    let closed: Int?
    let archived: Int?
    let bumplimit: Int?
    let imagelimit: Int?

    var isOP: Bool { resto == 0 }
    var thumbnailURL: URL? {
        guard let tim, let board = _board else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")
    }
    var imageURL: URL? {
        guard let tim, let ext, let board = _board else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)\(ext)")
    }

    /// Injected after decode — not part of API response
    var _board: String?

    var decodedSubject: String? { sub.map { PostHTMLRenderer.decodeEntities($0) } }

    /// Plain text with HTML stripped and entities decoded — used for previews and notifications.
    var plainTextComment: String? {
        guard let com else { return nil }
        return PostHTMLRenderer.plainText(com)
    }

    enum CodingKeys: String, CodingKey {
        case no, now, name, trip, id, capcode, com, sub, tim
        case filename, ext, fsize, w, h, md5, resto, replies, images
        case sticky, closed, archived, bumplimit, imagelimit
        case tnW = "tn_w"
        case tnH = "tn_h"
    }
}

struct ThreadResponse: Codable, Sendable {
    let posts: [Post]
}
