import Foundation

/// Constructs the `multipart/form-data` body used by 4chan's `/{board}/post`
/// endpoint for both replies (`resto > 0`) and new threads (`resto == 0`).
///
/// Pulled out of `ChanPostAPI` so the wire format can be unit-tested without
/// hitting the network.
enum PostFormBuilder {

    /// Optional file upload attached to a post.
    struct Attachment {
        let fieldName: String
        let filename: String
        let mimeType: String
        let data: Data
    }

    /// Builds the full multipart body. Fields are emitted in a deterministic
    /// order so tests can assert against the serialized output.
    static func buildBody(
        boundary: String,
        threadNo: Int,
        comment: String,
        subject: String?,
        name: String?,
        options: String?,
        flag: String?,
        attachment: Attachment?
    ) -> Data {
        var body = Data()

        // Required fields
        appendField(&body, boundary: boundary, name: "resto", value: "\(threadNo)")
        appendField(&body, boundary: boundary, name: "com", value: comment)
        appendField(&body, boundary: boundary, name: "mode", value: "regist")

        // OP-only / optional poster fields
        if let subject, !subject.isEmpty {
            appendField(&body, boundary: boundary, name: "sub", value: subject)
        }
        if let name, !name.isEmpty {
            appendField(&body, boundary: boundary, name: "name", value: name)
        }
        if let options, !options.isEmpty {
            // 4chan repurposes the "email" field for `sage` and other options.
            appendField(&body, boundary: boundary, name: "email", value: options)
        }

        // Optional meme flag (boards like /pol/)
        if let flag, !flag.isEmpty {
            appendField(&body, boundary: boundary, name: "flag", value: flag)
        }

        // Optional image attachment (required for new threads, optional for replies)
        if let attachment {
            appendFile(
                &body,
                boundary: boundary,
                name: attachment.fieldName,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                data: attachment.data
            )
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// Maps a filename extension to the MIME type 4chan expects for uploads.
    static func mimeType(forFilename filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webm":        return "video/webm"
        default:            return "application/octet-stream"
        }
    }

    // MARK: - Private

    private static func appendField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private static func appendFile(_ body: inout Data, boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }
}
