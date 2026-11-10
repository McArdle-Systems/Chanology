import Foundation
import SwiftData

/// The single poll pass shared by foreground polling (`ForegroundRefreshService`) and
/// background app refresh (`BackgroundRefreshHandler`).
///
/// Each live thread is fetched once per pass, whether it's watched, replied in, or both:
/// - **Watched**: notify for every new post (direct replies get the "(You)" treatment).
/// - **Replied in, not watched**: notify only for new direct replies to the user's posts.
/// - **Replied in** (watched or not): keep `MyPosts.directReplyCount` current for the catalog.
@MainActor
enum ThreadPoller {
    private struct Target {
        let board: String
        let threadNo: Int
        var watched: WatchedThread?
        var myPosts: MyPosts?
        var key: String { MyPosts.key(board: board, threadNo: threadNo) }
    }

    /// - Parameters:
    ///   - onFetched: called with each thread's key, fresh posts, and whether it's watched
    ///     (to update in-memory caches).
    ///   - onGone: called with the key of each thread that 404'd.
    static func pollOnce(
        context: ModelContext,
        onFetched: (String, [Post], Bool) -> Void = { _, _, _ in },
        onGone: (String) -> Void = { _ in }
    ) async {
        for target in targets(context: context) {
            guard !Task.isCancelled else { break }

            do {
                let posts = try await ChanAPI.shared.thread(board: target.board, no: target.threadNo)
                onFetched(target.key, posts, target.watched != nil)
                await apply(posts: posts, to: target)
                try? context.save()
            } catch ChanAPIError.notFound {
                // Pruned: drop it from the watch list, stop polling the replied-in record.
                if let watched = target.watched { context.delete(watched) }
                target.myPosts?.isGone = true
                try? context.save()
                onGone(target.key)
            } catch {
                // Network error, rate limit, etc. — try again next pass.
            }

            // Throttle: 1 second between requests (4chan rate limit)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Union of pollable watched threads and pollable replied-in threads, one entry per thread.
    private static func targets(context: ModelContext) -> [Target] {
        let watched = (try? context.fetch(FetchDescriptor<WatchedThread>())) ?? []
        let mine = (try? context.fetch(FetchDescriptor<MyPosts>())) ?? []
        let mineByKey = Dictionary(mine.map { ($0.threadKey, $0) }, uniquingKeysWith: { first, _ in first })

        var targets: [Target] = []
        var seen: Set<String> = []
        for thread in watched where thread.shouldPoll {
            let key = MyPosts.key(board: thread.board, threadNo: thread.threadNo)
            guard seen.insert(key).inserted else { continue }
            targets.append(Target(board: thread.board, threadNo: thread.threadNo, watched: thread, myPosts: mineByKey[key]))
        }
        for record in mine where record.shouldPoll && record.threadNo != 0 {
            guard seen.insert(record.threadKey).inserted else { continue }
            targets.append(Target(board: record.board, threadNo: record.threadNo, watched: nil, myPosts: record))
        }
        return targets
    }

    private static func apply(posts: [Post], to target: Target) async {
        guard let lastPostNo = posts.last?.no else { return }
        let isClosed = (posts.first?.closed ?? 0) != 0
        let isArchived = (posts.first?.archived ?? 0) != 0
        let myPostNumbers = Set(target.myPosts?.postNumbers ?? [])

        if let watched = target.watched {
            let newPosts = posts.filter { $0.no > watched.lastSeenPostNo }
            if !newPosts.isEmpty {
                await NotificationService.shared.notify(
                    board: target.board, threadNo: target.threadNo, subject: watched.subject,
                    newPosts: newPosts, myPostNumbers: myPostNumbers
                )
                watched.lastSeenPostNo = lastPostNo
                watched.newReplyCount += newPosts.count
                watched.lastChecked = Date()
            }
            watched.isClosed = isClosed
            watched.isArchived = isArchived
        }

        if let mine = target.myPosts {
            if mine.subject.isEmpty {
                mine.subject = target.watched?.subject ?? ReplyTracking.fallbackSubject(op: posts.first)
            }
            // Watched threads already notified above; only notify here for replied-only threads.
            // lastSeenPostNo == 0 means first poll of a pre-existing record: baseline silently.
            if target.watched == nil, mine.lastSeenPostNo > 0 {
                let newReplies = ReplyTracking.directReplies(
                    in: posts.filter { $0.no > mine.lastSeenPostNo },
                    myPostNumbers: myPostNumbers
                )
                if !newReplies.isEmpty {
                    await NotificationService.shared.notify(
                        board: target.board, threadNo: target.threadNo, subject: mine.subject,
                        newPosts: newReplies, myPostNumbers: myPostNumbers
                    )
                }
            }
            mine.lastSeenPostNo = max(mine.lastSeenPostNo, lastPostNo)
            mine.directReplyCount = ReplyTracking.directReplies(in: posts, myPostNumbers: myPostNumbers).count
            mine.isArchived = isArchived
        }
    }
}
