import UIKit
@preconcurrency import BackgroundTasks
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerBackgroundTasks()
        requestNotificationPermission()
        BackgroundRefreshHandler.scheduleRefresh()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshHandler.taskIdentifier,
            using: nil
        ) { task in
            BackgroundRefreshHandler.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // Show notification banners even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let board = userInfo["board"] as? String,
              let threadNo = userInfo["threadNo"] as? Int else { return }
        let subject = userInfo["subject"] as? String ?? "Thread #\(threadNo)"
        await MainActor.run {
            NavigationCoordinator.shared.openThread(board: board, threadNo: threadNo, subject: subject)
        }
    }
}
