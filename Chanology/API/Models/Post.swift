import Foundation

/// A single post within a thread (from the thread endpoint)
struct Post: Codable, Identifiable, Sendable {
    let no: Int              // Post number (unique ID)
    let now: String          // Date string "MM/DD/YY(Day)HH:MM:SS"
    let name: String?        // Poster name
    let trip: String?        // Tripcode
    let posterID: String?    // Poster ID (on boards that show it)
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
    let mobileImg: Int?      // 1 if a mobile-optimized image exists
    let resto: Int           // 0 if OP, else thread number this replies to
    let replies: Int?        // Reply count (OP only)
    let images: Int?         // Image count (OP only)
    let sticky: Int?
    let closed: Int?
    let archived: Int?
    let bumplimit: Int?
    let imagelimit: Int?
    let country: String?         // ISO country code (e.g. "US") — boards with flags
    let countryName: String?     // Full country name (e.g. "United States")
    let boardFlag: String?       // Board-specific meme flag code (e.g. "AC")
    let flagName: String?        // Meme flag display name (e.g. "Anarcho-Capitalist")

    var id: Int { no }
    var isOP: Bool { resto == 0 }
    var thumbnailURL: URL? {
        guard let tim, let board = _board else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")
    }
    var imageURL: URL? {
        guard let tim, let ext, let board = _board else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)\(ext)")
    }
    var mobileImageURL: URL? {
        guard mobileImg == 1, let tim, let board = _board else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)m.jpg")
    }
    // Aspect ratio (h/w) derived from full image dimensions, falling back to thumbnail dims.
    // Used by views to pre-size placeholder slots before the image loads.
    var imageAspectRatio: Double? {
        let imgW = w ?? tnW
        let imgH = h ?? tnH
        guard let imgW, let imgH, imgW > 0 else { return nil }
        return Double(imgH) / Double(imgW)
    }

    /// Injected after decode — not part of API response
    var _board: String?

    var decodedSubject: String? { sub.map { PostHTMLRenderer.decodeEntities($0) } }

    /// Plain text with HTML stripped and entities decoded — used for previews and notifications.
    var plainTextComment: String? {
        guard let com else { return nil }
        return PostHTMLRenderer.plainText(com)
    }

    /// URL for the board-specific meme flag image.
    var boardFlagURL: URL? {
        guard let boardFlag, let board = _board else { return nil }
        return URL(string: "https://s.4cdn.org/image/flags/\(board)/\(boardFlag.lowercased()).gif")
    }

    /// Emoji flag derived from ISO country code (e.g. "US" → "🇺🇸").
    var countryEmoji: String? {
        guard let country, country.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6 - 65 // Regional indicator 'A'
        let scalars = country.uppercased().unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            Unicode.Scalar(base + scalar.value)
        }
        guard scalars.count == 2 else { return nil }
        return String(scalars.map { Character($0) })
    }

    enum CodingKeys: String, CodingKey {
        case no, now, name, trip, capcode, com, sub, tim
        case filename, ext, fsize, w, h, md5, resto, replies, images
        case sticky, closed, archived, bumplimit, imagelimit
        case country
        case flagName = "flag_name"
        case posterID = "id"
        case tnW = "tn_w"
        case tnH = "tn_h"
        case mobileImg = "m_img"
        case countryName = "country_name"
        case boardFlag = "board_flag"
    }
}

struct ThreadResponse: Codable, Sendable {
    let posts: [Post]
}
