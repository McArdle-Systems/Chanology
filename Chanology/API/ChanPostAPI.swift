import Foundation

/// Handles posting to 4chan via sys.4chan.org.
/// Separate from ChanAPI (read-only) because posting uses different auth and endpoints.
actor ChanPostAPI {
    static let shared = ChanPostAPI()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Chanology/1.0 iOS"]
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    /// Whether we have a valid pass_id cookie for sys.4chan.org.
    nonisolated var isAuthenticated: Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://sys.4chan.org")!) else {
            return false
        }
        return cookies.contains { $0.name == "pass_id" && !$0.value.isEmpty && $0.value != "0" }
    }

    /// Authenticate with a 4chan Pass token and PIN.
    /// On success, the pass_id cookie is stored in shared cookie storage.
    func authenticate(token: String, pin: String) async throws {
        guard let url = URL(string: "https://sys.4chan.org/auth") else {
            throw PostAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "act=do_login&id=\(urlEncode(token))&pin=\(urlEncode(pin))"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PostAPIError.invalidResponse
        }

        // Check if we got a pass_id cookie
        if isAuthenticated {
            // Save credentials for future re-auth
            KeychainHelper.passToken = token
            KeychainHelper.passPIN = pin
            return
        }

        // Parse error from response body
        let responseText = String(data: data, encoding: .utf8) ?? ""
        if responseText.contains("Incorrect Token/PIN") || http.statusCode == 403 {
            throw PostAPIError.authFailed("Incorrect Token or PIN")
        }
        throw PostAPIError.authFailed("Authentication failed (HTTP \(http.statusCode))")
    }

    /// Try to re-authenticate using saved Keychain credentials.
    func reauthenticateIfNeeded() async throws {
        guard !isAuthenticated else { return }
        guard let token = KeychainHelper.passToken, let pin = KeychainHelper.passPIN else {
            throw PostAPIError.notAuthenticated
        }
        try await authenticate(token: token, pin: pin)
    }

    // MARK: - Posting

    /// Submit a post (reply) to a thread.
    /// Returns the new post number on success.
    @discardableResult
    func submitPost(
        board: String,
        threadNo: Int,
        comment: String,
        name: String? = nil,
        options: String? = nil,
        imageData: Data? = nil,
        imageFilename: String? = nil,
        flag: String? = nil
    ) async throws -> Int {
        try await submitForm(
            board: board,
            threadNo: threadNo,
            subject: nil,
            name: name,
            options: options,
            comment: comment,
            imageData: imageData,
            imageFilename: imageFilename,
            flag: flag
        )
    }

    /// Submit a new top-level thread (OP) on a board.
    /// Returns the new thread number on success.
    @discardableResult
    func submitNewThread(
        board: String,
        subject: String?,
        name: String?,
        options: String?,
        comment: String,
        imageData: Data,
        imageFilename: String,
        flag: String? = nil
    ) async throws -> Int {
        try await submitForm(
            board: board,
            threadNo: 0,
            subject: subject,
            name: name,
            options: options,
            comment: comment,
            imageData: imageData,
            imageFilename: imageFilename,
            flag: flag
        )
    }

    /// Internal multipart submission used by both reply and new-thread paths.
    private func submitForm(
        board: String,
        threadNo: Int,
        subject: String?,
        name: String?,
        options: String?,
        comment: String,
        imageData: Data?,
        imageFilename: String?,
        flag: String?
    ) async throws -> Int {
        // Re-auth if cookie expired
        try await reauthenticateIfNeeded()

        guard let url = URL(string: "https://sys.4chan.org/\(board)/post") else {
            throw PostAPIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let attachment: PostFormBuilder.Attachment? = {
            guard let imageData, let imageFilename else { return nil }
            return PostFormBuilder.Attachment(
                fieldName: "upfile",
                filename: imageFilename,
                mimeType: PostFormBuilder.mimeType(forFilename: imageFilename),
                data: imageData
            )
        }()

        request.httpBody = PostFormBuilder.buildBody(
            boundary: boundary,
            threadNo: threadNo,
            comment: comment,
            subject: subject,
            name: name,
            options: options,
            flag: flag,
            attachment: attachment
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PostAPIError.invalidResponse
        }

        let responseText = String(data: data, encoding: .utf8) ?? ""

        // 4chan returns HTML response — check for success or error
        if http.statusCode == 200, responseText.contains("Post successful") {
            // Try to extract post number from response
            if let match = responseText.firstMatch(of: /no:(\d+)/) {
                return Int(match.output.1) ?? 0
            }
            return 0
        }

        // Parse error message from HTML
        if let match = responseText.firstMatch(of: /id="errmsg"[^>]*>([^<]+)</) {
            throw PostAPIError.postFailed(String(match.output.1))
        }

        if http.statusCode == 403 {
            throw PostAPIError.notAuthenticated
        }

        throw PostAPIError.postFailed("Post failed (HTTP \(http.statusCode))")
    }

    // MARK: - Helpers

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}

enum PostAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case authFailed(String)
    case postFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .invalidResponse: "Invalid response from server"
        case .notAuthenticated: "Not authenticated — please log in with your 4chan Pass"
        case .authFailed(let msg): "Login failed: \(msg)"
        case .postFailed(let msg): "Post failed: \(msg)"
        }
    }
}
