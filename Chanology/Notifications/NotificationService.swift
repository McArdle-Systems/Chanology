import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    func notify(board: String, threadNo: Int, subject: String, newPosts: [Post], myPostNumbers: Set<Int> = []) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        print("[Notifications] Authorization status: \(settings.authorizationStatus.rawValue) (2 = authorized)")
        guard settings.authorizationStatus == .authorized else {
            print("[Notifications] Not authorized, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "/\(board)/ — \(subject)"

        let directReplies = myPostNumbers.isEmpty ? [] : newPosts.filter { post in
            ReplyMapBuilder.quotedPosts(in: post).contains(where: myPostNumbers.contains)
        }
        let otherCount = newPosts.count - directReplies.count

        if directReplies.count == 1 && otherCount == 0 {
            // Single direct reply — show its text with a prefix
            let text = directReplies[0].plainTextComment?.prefix(200).description ?? "New reply"
            content.body = "@(You): \(text)"
        } else if directReplies.count > 1 && otherCount == 0 {
            content.body = "\(directReplies.count) replies to you"
        } else if directReplies.count > 0 {
            content.body = "\(directReplies.count) \(directReplies.count == 1 ? "reply" : "replies") to you + \(otherCount) \(otherCount == 1 ? "other" : "others")"
        } else if newPosts.count == 1, let comment = newPosts[0].plainTextComment {
            content.body = comment.prefix(200).description
        } else {
            content.body = "\(newPosts.count) new replies"
        }

        let soundEnabled = UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true
        content.sound = soundEnabled ? .default : nil
        content.userInfo = ["board": board, "threadNo": threadNo, "subject": subject]

        let request = UNNotificationRequest(
            identifier: "\(board)-\(threadNo)-\(newPosts.first?.no ?? 0)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            print("[Notifications] Delivered: \(content.title) — \(content.body)")
        } catch {
            print("[Notifications] Failed to deliver: \(error)")
        }
    }
}
