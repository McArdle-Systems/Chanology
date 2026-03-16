import Foundation

/// Pure functions for determining new-replies marker placement and read-state updates.
///
/// Extracted from ThreadView so the logic can be unit tested without SwiftUI dependencies.
enum ThreadRefreshLogic {

    /// Result of computing where the "New Replies" marker should go after a refresh.
    struct MarkerResult: Equatable {
        /// The post number where the marker should appear, or `nil` to clear it.
        let markerPostNo: Int?
    }

    /// Result of computing watched-thread read-state updates after a user-initiated refresh.
    struct ReadStateUpdate: Equatable {
        let lastReadPostNo: Int
        let lastSeenPostNo: Int
        let newReplyCount: Int
    }

    /// Result of computing watched-thread state updates after an auto-refresh.
    struct AutoRefreshUpdate: Equatable {
        let markerPostNo: Int?
        let lastSeenPostNo: Int
        let newReplyCount: Int
    }

    // MARK: - User-initiated refresh

    /// Determines where to place (or clear) the "New Replies" marker after a user-initiated refresh.
    ///
    /// - Parameters:
    ///   - lastPostNoBefore: The last post number before the refresh, or `nil` if the thread was empty.
    ///   - postNosAfter: All post numbers after the refresh, in order.
    /// - Returns: The marker position (or `nil` to clear).
    static func markerAfterUserRefresh(
        lastPostNoBefore: Int?,
        postNosAfter: [Int]
    ) -> MarkerResult {
        guard let lastPostNoBefore,
              let firstNew = postNosAfter.first(where: { $0 > lastPostNoBefore }) else {
            return MarkerResult(markerPostNo: nil)
        }
        return MarkerResult(markerPostNo: firstNew)
    }

    /// Computes the read-state update for a watched thread after a user-initiated refresh.
    ///
    /// - Parameter postNosAfter: All post numbers after the refresh, in order.
    /// - Returns: The new read-state values, or `nil` if the thread has no posts.
    static func readStateAfterUserRefresh(
        postNosAfter: [Int]
    ) -> ReadStateUpdate? {
        guard let lastPost = postNosAfter.last else { return nil }
        return ReadStateUpdate(
            lastReadPostNo: lastPost,
            lastSeenPostNo: lastPost,
            newReplyCount: 0
        )
    }

    // MARK: - Auto-refresh

    /// Determines the marker and watched-thread updates after an auto-refresh.
    ///
    /// - Parameters:
    ///   - currentMarkerPostNo: The current marker position (may be `nil`).
    ///   - lastReadPostNo: The last-read boundary from the watched thread.
    ///   - lastSeenPostNo: The last-seen boundary from the watched thread.
    ///   - postNosAfter: All post numbers after the refresh, in order.
    /// - Returns: The new marker + state, or `nil` if the thread has no posts.
    static func autoRefreshUpdate(
        currentMarkerPostNo: Int?,
        lastReadPostNo: Int,
        lastSeenPostNo: Int,
        postNosAfter: [Int]
    ) -> AutoRefreshUpdate? {
        guard let lastPost = postNosAfter.last else { return nil }

        // Only place a marker if one doesn't already exist
        var newMarker = currentMarkerPostNo
        if currentMarkerPostNo == nil,
           let firstNew = postNosAfter.first(where: { $0 > lastReadPostNo }) {
            newMarker = firstNew.self
        }

        let newPostCount = postNosAfter.filter { $0 > lastSeenPostNo }.count

        return AutoRefreshUpdate(
            markerPostNo: newMarker,
            lastSeenPostNo: lastPost,
            newReplyCount: newPostCount
        )
    }

    // MARK: - Initial load

    /// Determines the marker position when first opening a thread (from the watch list).
    ///
    /// - Parameters:
    ///   - lastReadPostNo: The last-read boundary from the watched thread, or `nil` if not watched.
    ///   - postNos: All post numbers after loading, in order.
    /// - Returns: The marker position (or `nil` if no unread posts).
    static func markerOnInitialLoad(
        lastReadPostNo: Int?,
        postNos: [Int]
    ) -> MarkerResult {
        guard let lastRead = lastReadPostNo,
              let firstNew = postNos.first(where: { $0 > lastRead }) else {
            return MarkerResult(markerPostNo: nil)
        }
        return MarkerResult(markerPostNo: firstNew)
    }

    // MARK: - Visible-posts read tracking

    /// Computes updated read state after the user scrolls (visible posts change).
    ///
    /// - Parameters:
    ///   - visiblePosts: The set of currently visible post numbers.
    ///   - allPostNos: All post numbers in the thread, in order.
    ///   - currentLastReadPostNo: The current last-read boundary.
    /// - Returns: A tuple of (newLastReadPostNo, markerPostNo) or `nil` if no update needed.
    static func readStateAfterScroll(
        visiblePosts: Set<Int>,
        allPostNos: [Int],
        currentLastReadPostNo: Int
    ) -> (newLastReadPostNo: Int, markerPostNo: Int?)? {
        guard !visiblePosts.isEmpty else { return nil }

        let highestVisible = visiblePosts.max()!

        guard highestVisible > currentLastReadPostNo else { return nil }

        // Marker moves to the first post after what we've now read
        let markerPostNo = allPostNos.first(where: { $0 > highestVisible })

        return (newLastReadPostNo: highestVisible, markerPostNo: markerPostNo)
    }
}
