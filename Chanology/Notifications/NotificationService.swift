import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    func notify(board: String, threadNo: Int, subject: String, newPosts: [Post]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "/\(board)/ — \(subject)"

        if newPosts.count == 1, let comment = newPosts[0].plainTextComment {
            content.body = comment.prefix(200).description
        } else {
            content.body = "\(newPosts.count) new replies"
        }

        content.sound = .default
        content.userInfo = ["board": board, "threadNo": threadNo]

        let request = UNNotificationRequest(
            identifier: "\(board)-\(threadNo)-\(newPosts.first?.no ?? 0)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}
