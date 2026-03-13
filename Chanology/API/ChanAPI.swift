import Foundation

/// Typed, async 4chan API client.
/// Respects 4chan's informal rate limit of ~1 req/sec via serial execution from callers.
actor ChanAPI {
    static let shared = ChanAPI()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = "https://a.4cdn.org"

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Chanology/1.0 iOS"]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // MARK: - Boards

    func boards() async throws -> [Board] {
        let response: BoardsResponse = try await fetch(path: "/boards.json")
        return response.boards
    }

    // MARK: - Catalog

    func catalog(board: String) async throws -> [CatalogThread] {
        let pages: [CatalogPage] = try await fetch(path: "/\(board)/catalog.json")
        return pages.flatMap { page in
            page.threads.map { thread in
                var t = thread
                t._board = board
                return t
            }
        }
    }

    // MARK: - Thread

    func thread(board: String, no: Int) async throws -> [Post] {
        let response: ThreadResponse = try await fetch(path: "/\(board)/thread/\(no).json")
        return response.posts.map { post in
            var p = post
            p._board = board
            return p
        }
    }

    // MARK: - Private

    private func fetch<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw ChanAPIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ChanAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            return try decoder.decode(T.self, from: data)
        case 404:
            throw ChanAPIError.notFound
        case 429:
            throw ChanAPIError.rateLimited
        default:
            throw ChanAPIError.httpError(http.statusCode)
        }
    }
}

enum ChanAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .invalidResponse: "Invalid response from server"
        case .notFound: "Thread or board not found (404)"
        case .rateLimited: "Rate limited — slow down requests"
        case .httpError(let code): "HTTP error \(code)"
        }
    }
}
