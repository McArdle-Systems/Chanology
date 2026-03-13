import UIKit
@preconcurrency import BackgroundTasks
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerBackgroundTasks()
        requestNotificationPermission()
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

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundRefreshHandler.scheduleRefresh()
    }
}
