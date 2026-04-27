import Foundation
import SwiftData

/// Centralized data service that owns all API-fetched data (boards, catalogs, threads).
///
/// Views read directly from this service's `@Observable` properties, so SwiftUI re-renders
/// automatically when data changes. The service also runs a background polling loop for
/// watched threads while the app is in the foreground.
///
/// ## Architecture
/// - **Single source of truth** for boards, catalog, and thread post data.
/// - **Foreground polling** of watched threads every 30 seconds (replaces per-ThreadView timers).
/// - **On-demand fetching** for boards/catalogs (pull-to-refresh, `.task` on appear).
/// - Views no longer maintain their own ViewModels or copies of API data.
@Observable
@MainActor
final class ForegroundRefreshService {
    // MARK: - Shared instance

    static let shared = ForegroundRefreshService()

    // MARK: - Boards

    var boards: [Board] = []
    var boardsLoading = false
    var boardsError: Error?

    var workSafeBoards: [Board] { boards.filter(\.isWorkSafe) }
    var nsfwBoards: [Board] { boards.filter { !$0.isWorkSafe } }

    // MARK: - Catalogs (keyed by board code)

    var catalogs: [String: [CatalogThread]] = [:]
    var catalogLoading: [String: Bool] = [:]
    var catalogError: [String: Error] = [:]

    // MARK: - Thread posts (keyed by "board/threadNo")

    var threadPosts: [String: [Post]] = [:]
    var threadLoading: [String: Bool] = [:]
    var threadError: [String: Error] = [:]

    // MARK: - Polling

    private var pollingTask: Task<Void, Never>?
    private(set) var isPolling = false

    /// The model container used for SwiftData operations (watched threads).
    /// Must be set before starting the polling loop.
    var modelContainer: ModelContainer?

    // MARK: - Keys

    static func threadKey(board: String, threadNo: Int) -> String {
        "\(board)/\(threadNo)"
    }

    // MARK: - Boards API

    func fetchBoards() async {
        let isInitialLoad = boards.isEmpty
        if isInitialLoad { boardsLoading = true }
        defer { boardsLoading = false }
        do {
            boards = try await ChanAPI.shared.boards()
            boardsError = nil
        } catch {
            boardsError = error
        }
    }

    // MARK: - Catalog API

    func fetchCatalog(board: String) async {
        let isInitialLoad = catalogs[board] == nil
        if isInitialLoad { catalogLoading[board] = true }
        defer { catalogLoading[board] = false }
        do {
            catalogs[board] = try await ChanAPI.shared.catalog(board: board)
            catalogError.removeValue(forKey: board)
        } catch {
            catalogError[board] = error
        }
    }

    func catalogThreads(board: String) -> [CatalogThread] {
        catalogs[board] ?? []
    }

    func isCatalogLoading(board: String) -> Bool {
        catalogLoading[board] ?? false
    }

    // MARK: - Thread API

    func fetchThread(board: String, threadNo: Int) async {
        let key = Self.threadKey(board: board, threadNo: threadNo)
        let isInitialLoad = threadPosts[key] == nil
        if isInitialLoad { threadLoading[key] = true }
        defer { threadLoading[key] = false }
        do {
            threadPosts[key] = try await ChanAPI.shared.thread(board: board, no: threadNo)
            threadError.removeValue(forKey: key)
        } catch {
            threadError[key] = error
        }
    }

    func posts(board: String, threadNo: Int) -> [Post] {
        threadPosts[Self.threadKey(board: board, threadNo: threadNo)] ?? []
    }

    func isThreadLoading(board: String, threadNo: Int) -> Bool {
        threadLoading[Self.threadKey(board: board, threadNo: threadNo)] ?? false
    }

    func getThreadError(board: String, threadNo: Int) -> Error? {
        threadError[Self.threadKey(board: board, threadNo: threadNo)]
    }

    func clearThreadError(board: String, threadNo: Int) {
        threadError.removeValue(forKey: Self.threadKey(board: board, threadNo: threadNo))
    }

    /// Evict cached posts for a thread (e.g., when no longer viewing it and it's not watched).
    func evictThread(board: String, threadNo: Int) {
        let key = Self.threadKey(board: board, threadNo: threadNo)
        threadPosts.removeValue(forKey: key)
        threadLoading.removeValue(forKey: key)
        threadError.removeValue(forKey: key)
    }

    // MARK: - Foreground Polling

    /// Start the foreground polling loop for watched threads.
    /// Call this when the app enters the foreground.
    func startPolling() {
        guard pollingTask == nil else { return }
        isPolling = true
        pollingTask = Task {
            while !Task.isCancelled {
                await pollWatchedThreads()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Stop the foreground polling loop.
    /// Call this when the app enters the background.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    /// Single poll pass: fetch each watched thread, update SwiftData + in-memory posts.
    private func pollWatchedThreads() async {
        guard let container = modelContainer else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<WatchedThread>()
        guard let watchedThreads = try? context.fetch(descriptor), !watchedThreads.isEmpty else { return }

        for watched in watchedThreads {
            guard !Task.isCancelled else { break }

            let board = watched.board
            let threadNo = watched.threadNo
            let key = Self.threadKey(board: board, threadNo: threadNo)

            do {
                let posts = try await ChanAPI.shared.thread(board: board, no: threadNo)

                // Update in-memory cache (drives ThreadView if it's open)
                threadPosts[key] = posts

                // Update SwiftData watched thread state
                let newPosts = posts.filter { $0.no > watched.lastSeenPostNo }
                if !newPosts.isEmpty {
                    let myPostsKey = MyPosts.key(board: board, threadNo: threadNo)
                    let myPostsDescriptor = FetchDescriptor<MyPosts>(predicate: #Predicate { $0.threadKey == myPostsKey })
                    let myPostNumbers = Set((try? context.fetch(myPostsDescriptor))?.first?.postNumbers ?? [])
                    await NotificationService.shared.notify(
                        board: board,
                        threadNo: threadNo,
                        subject: watched.subject,
                        newPosts: newPosts,
                        myPostNumbers: myPostNumbers
                    )
                    watched.lastSeenPostNo = posts.last!.no
                    watched.newReplyCount += newPosts.count
                    watched.lastChecked = Date()
                    try? context.save()
                }
            } catch ChanAPIError.notFound {
                // Thread 404'd — remove from watch list
                context.delete(watched)
                try? context.save()
                threadPosts.removeValue(forKey: key)
            } catch {
                // Network error — skip, try next time
                continue
            }

            // Throttle: 1 second between requests (4chan rate limit)
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
