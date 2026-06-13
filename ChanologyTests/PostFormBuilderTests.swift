import Testing
import Foundation
@testable import Chanology

// MARK: - Helpers

private let testBoundary = "TEST-BOUNDARY-1234"

private func decodedBody(
    threadNo: Int = 0,
    comment: String = "hello",
    subject: String? = nil,
    name: String? = nil,
    options: String? = nil,
    flag: String? = nil,
    attachment: PostFormBuilder.Attachment? = nil
) -> String {
    let data = PostFormBuilder.buildBody(
        boundary: testBoundary,
        threadNo: threadNo,
        comment: comment,
        subject: subject,
        name: name,
        options: options,
        flag: flag,
        attachment: attachment
    )
    return String(data: data, encoding: .utf8) ?? ""
}

private func fieldBlock(name: String, value: String) -> String {
    "--\(testBoundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
}

// MARK: - Required fields

@Test func body_reply_alwaysIncludesRequiredFields() {
    let body = decodedBody(threadNo: 12345, comment: "Hi there")
    #expect(body.contains(fieldBlock(name: "resto", value: "12345")))
    #expect(body.contains(fieldBlock(name: "com", value: "Hi there")))
    #expect(body.contains(fieldBlock(name: "mode", value: "regist")))
}

@Test func body_newThread_usesRestoZero() {
    let body = decodedBody(threadNo: 0, comment: "OP")
    #expect(body.contains(fieldBlock(name: "resto", value: "0")))
}

@Test func body_endsWithClosingBoundary() {
    let body = decodedBody()
    #expect(body.hasSuffix("--\(testBoundary)--\r\n"))
}

// MARK: - Optional poster fields

@Test func body_omitsSubjectName_andEmail_whenNilOrEmpty() {
    let body = decodedBody(subject: nil, name: nil, options: nil)
    #expect(!body.contains("name=\"sub\""))
    #expect(!body.contains("name=\"name\""))
    #expect(!body.contains("name=\"email\""))
}

@Test func body_includesSubject_whenProvided() {
    let body = decodedBody(subject: "My subject")
    #expect(body.contains(fieldBlock(name: "sub", value: "My subject")))
}

@Test func body_includesName_whenProvided() {
    let body = decodedBody(name: "Anon")
    #expect(body.contains(fieldBlock(name: "name", value: "Anon")))
}

@Test func body_optionsMapsToEmailField() {
    // 4chan repurposes the email field for `sage` and other options.
    let body = decodedBody(options: "sage")
    #expect(body.contains(fieldBlock(name: "email", value: "sage")))
}

@Test func body_omitsEmptyStringFields() {
    let body = decodedBody(subject: "", name: "", options: "")
    #expect(!body.contains("name=\"sub\""))
    #expect(!body.contains("name=\"name\""))
    #expect(!body.contains("name=\"email\""))
}

// MARK: - Flag field

@Test func body_includesFlag_whenProvided() {
    let body = decodedBody(flag: "NZ")
    #expect(body.contains(fieldBlock(name: "flag", value: "NZ")))
}

@Test func body_omitsFlag_whenNil() {
    let body = decodedBody(flag: nil)
    #expect(!body.contains("name=\"flag\""))
}

// MARK: - Attachment

@Test func body_omitsUpfile_whenNoAttachment() {
    let body = decodedBody(attachment: nil)
    #expect(!body.contains("name=\"upfile\""))
}

@Test func body_includesUpfile_headers_andData() {
    let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let attachment = PostFormBuilder.Attachment(
        fieldName: "upfile",
        filename: "kitten.png",
        mimeType: "image/png",
        data: payload
    )
    let bodyData = PostFormBuilder.buildBody(
        boundary: testBoundary,
        threadNo: 0,
        comment: "OP",
        subject: nil, name: nil, options: nil, flag: nil,
        attachment: attachment
    )
    // Validate the multipart headers as a UTF-8 substring
    let asString = String(decoding: bodyData, as: UTF8.self)
    #expect(asString.contains("Content-Disposition: form-data; name=\"upfile\"; filename=\"kitten.png\""))
    #expect(asString.contains("Content-Type: image/png"))

    // Validate the raw bytes are present somewhere in the body
    #expect(bodyData.range(of: payload) != nil)
}

// MARK: - MIME type detection

@Test func mimeType_jpg_jpeg() {
    #expect(PostFormBuilder.mimeType(forFilename: "x.jpg") == "image/jpeg")
    #expect(PostFormBuilder.mimeType(forFilename: "x.jpeg") == "image/jpeg")
    #expect(PostFormBuilder.mimeType(forFilename: "X.JPG") == "image/jpeg")
}

@Test func mimeType_png() {
    #expect(PostFormBuilder.mimeType(forFilename: "image.png") == "image/png")
}

@Test func mimeType_gif() {
    #expect(PostFormBuilder.mimeType(forFilename: "anim.gif") == "image/gif")
}

@Test func mimeType_webm() {
    #expect(PostFormBuilder.mimeType(forFilename: "clip.webm") == "video/webm")
}

@Test func mimeType_unknown_defaultsToOctetStream() {
    #expect(PostFormBuilder.mimeType(forFilename: "weird.xyz") == "application/octet-stream")
    #expect(PostFormBuilder.mimeType(forFilename: "noext") == "application/octet-stream")
}
