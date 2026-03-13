import Foundation

/// A thread entry from the catalog endpoint
struct CatalogThread: Codable, Identifiable, Hashable, Sendable {
    let no: Int
    let now: String
    let name: String?
    let sub: String?
    let com: String?
    let tim: Int?
    let ext: String?
    let w: Int?
    let h: Int?
    let tnW: Int?
    let tnH: Int?
    let replies: Int
    let images: Int
    let sticky: Int?
    let closed: Int?
    let omittedPosts: Int?
    let omittedImages: Int?
    let lastModified: Int

    var id: Int { no }
    var _board: String?

    func thumbnailURL(board: String) -> URL? {
        guard let tim else { return nil }
        return URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")
    }

    var decodedSubject: String? { sub.map { PostHTMLRenderer.decodeEntities($0) } }

    var plainTextComment: String? {
        guard let com else { return nil }
        return PostHTMLRenderer.plainText(com)
    }

    enum CodingKeys: String, CodingKey {
        case no, now, name, sub, com, tim, ext, w, h, replies, images, sticky, closed
        case tnW = "tn_w"
        case tnH = "tn_h"
        case omittedPosts = "omitted_posts"
        case omittedImages = "omitted_images"
        case lastModified = "last_modified"
    }
}

struct CatalogPage: Codable, Sendable {
    let page: Int
    let threads: [CatalogThread]
}
