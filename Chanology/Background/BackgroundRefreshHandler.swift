import Foundation
@preconcurrency import BackgroundTasks
import SwiftData

enum BackgroundRefreshHandler {
    static let taskIdentifier = "io.mcardle.chanology.background.refresh"

    /// Called by BGTaskScheduler when the system grants background time.
    /// Budget: ~30 seconds. Keep this lean.
    static func handleAppRefresh(task: BGAppRefreshTask) {
        print("[BackgroundRefresh] Task fired")
        // Schedule the next refresh immediately so we don't miss a slot
        scheduleRefresh()

        let taskHandle = Task {
            await performRefresh()
        }

        task.expirationHandler = {
            taskHandle.cancel()
        }

        Task {
            await taskHandle.value
            task.setTaskCompleted(success: !taskHandle.isCancelled)
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Earliest fire date — iOS won't fire before this, but may fire much later.
        // 15 minutes is the practical minimum iOS will honor.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundRefresh] Scheduled refresh for ~15 min from now")
        } catch {
            print("[BackgroundRefresh] Failed to schedule: \(error)")
        }
    }

    /// The actual polling work. Fetches each watched thread and fires local
    /// notifications for new posts. Designed to complete well within 30s.
    /// Pass a `ModelContext` when calling from the UI to keep SwiftUI's @Query in sync.
    static func performRefresh(using existingContext: sending ModelContext? = nil) async {
        let context: ModelContext
        if let existingContext {
            context = existingContext
        } else {
            let container: ModelContainer
            do {
                let schema = Schema([WatchedThread.self])
                container = try ModelContainer(for: schema)
            } catch {
                return
            }
            context = ModelContext(container)
        }

        let descriptor = FetchDescriptor<WatchedThread>()

        guard let threads = try? context.fetch(descriptor), !threads.isEmpty else { return }

        // Process threads sequentially to respect 4chan's rate limit (~1 req/sec)
        for thread in threads {
            guard !Task.isCancelled else { break }

            do {
                let posts = try await ChanAPI.shared.thread(board: thread.board, no: thread.threadNo)
                let newPosts = posts.filter { $0.no > thread.lastSeenPostNo }

                if !newPosts.isEmpty {
                    let board = thread.board
                    let threadNo = thread.threadNo
                    let subject = thread.subject
                    await NotificationService.shared.notify(board: board, threadNo: threadNo, subject: subject, newPosts: newPosts)
                    thread.lastSeenPostNo = posts.last!.no
                    thread.newReplyCount += newPosts.count
                    thread.lastChecked = Date()
                    try? context.save()
                }
            } catch ChanAPIError.notFound {
                // Thread 404'd — it was pruned. Remove from watch list.
                context.delete(thread)
                try? context.save()
            } catch {
                // Network error, rate limit, etc. — skip this thread, try next time.
                continue
            }

            // Throttle: 1 second between requests
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
