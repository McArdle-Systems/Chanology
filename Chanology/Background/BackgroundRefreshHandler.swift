import Foundation
@preconcurrency import BackgroundTasks
import SwiftData

enum BackgroundRefreshHandler {
    static let taskIdentifier = "io.mcardle.chanology.background.refresh"

    /// Called by BGTaskScheduler when the system grants background time.
    /// Budget: ~30 seconds. Keep this lean.
    /// Must be nonisolated — BGTaskScheduler invokes this on a background thread.
    nonisolated static func handleAppRefresh(task: BGAppRefreshTask) {
        print("[BackgroundRefresh] Task fired")
        // Schedule the next refresh immediately so we don't miss a slot.
        // BGTaskScheduler.shared.submit requires @MainActor, so hop there.
        Task { @MainActor in scheduleRefresh() }

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

    @MainActor
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

    /// The actual polling work: one `ThreadPoller` pass over watched and replied-in
    /// threads. Designed to complete well within 30s.
    @MainActor
    static func performRefresh() async {
        let container: ModelContainer
        do {
            let schema = Schema([WatchedThread.self, MyPosts.self])
            container = try ModelContainer(for: schema)
        } catch {
            return
        }
        await ThreadPoller.pollOnce(context: ModelContext(container))
    }
}
