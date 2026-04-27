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

        let payload = NotificationService.buildContent(
            board: board, subject: subject, newPosts: newPosts, myPostNumbers: myPostNumbers
        )

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        let customSounds = UserDefaults.standard.object(forKey: "customNotificationSounds") as? Bool ?? true
        content.sound = (customSounds && payload.isDirectReply)
            ? UNNotificationSound(named: UNNotificationSoundName("Hey You.caf"))
            : .default
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

    // MARK: - Testable content builder

    struct Payload {
        let title: String
        let body: String
        let isDirectReply: Bool
    }

    static func buildContent(
        board: String,
        subject: String,
        newPosts: [Post],
        myPostNumbers: Set<Int>
    ) -> Payload {
        let title = "/\(board)/ — \(subject)"

        let directReplies = myPostNumbers.isEmpty ? [] : newPosts.filter { post in
            ReplyMapBuilder.quotedPosts(in: post).contains(where: myPostNumbers.contains)
        }
        let otherCount = newPosts.count - directReplies.count

        let body: String
        if directReplies.count == 1 && otherCount == 0 {
            let text = directReplies[0].plainTextComment?.prefix(200).description ?? "New reply"
            body = "@(You): \(text)"
        } else if directReplies.count > 1 && otherCount == 0 {
            body = "\(directReplies.count) replies to you"
        } else if directReplies.count > 0 {
            body = "\(directReplies.count) \(directReplies.count == 1 ? "reply" : "replies") to you + \(otherCount) \(otherCount == 1 ? "other" : "others")"
        } else if newPosts.count == 1, let comment = newPosts[0].plainTextComment {
            body = comment.prefix(200).description
        } else {
            body = "\(newPosts.count) new replies"
        }

        return Payload(title: title, body: body, isDirectReply: !directReplies.isEmpty)
    }
}
