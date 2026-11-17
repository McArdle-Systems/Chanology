#if DEBUG
import Foundation

/// Debug-only access to the tiny media fixtures in `ChanologyTests/Fixtures`
/// (64x48 test pattern: sample.jpg / .gif / .webm / .mp4), so Xcode previews can
/// show and open real attachments.
///
/// Files are read straight from the source tree via `#filePath` — previews and the
/// simulator run on this Mac and can see it. Nothing here ships in release builds.
enum PreviewMedia {
    static let fixturesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()   // Components
        .deletingLastPathComponent()   // UI
        .deletingLastPathComponent()   // Chanology
        .deletingLastPathComponent()   // repo root
        .appending(path: "ChanologyTests/Fixtures", directoryHint: .isDirectory)

    /// `ext` with or without the leading dot: "gif", ".webm", …
    static func url(_ ext: String) -> URL {
        fixturesDirectory.appending(path: "sample.\(ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")))")
    }

    /// The first frame doubles as the thumbnail for every fixture.
    static var thumbnailURL: URL { url("jpg") }

    /// A reply post with a local fixture attached.
    static func post(
        ext: String,
        filename: String = "sample",
        comment: String = "Post with an attachment",
        no: Int = 11111
    ) -> Post {
        let dottedExt = "." + ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let data = try! JSONSerialization.data(withJSONObject: [
            "no": no,
            "now": "01/01/25(Wed)12:30:00",
            "name": "Anonymous",
            "com": comment,
            "resto": 99999,
            "tim": 1234567890,
            "ext": dottedExt,
            "filename": filename,
            "w": 64,
            "h": 48,
        ] as [String: Any])
        var post = try! JSONDecoder().decode(Post.self, from: data)
        post._board = "g"
        post._debugMedia = .init(full: url(dottedExt), thumbnail: thumbnailURL)
        return post
    }
}
#endif
