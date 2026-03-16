import Testing
@testable import Chanology

// MARK: - markerAfterUserRefresh

@Test func userRefresh_newPostsArrive_markerAtFirstNew() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 100,
        postNosAfter: [50, 100, 150, 200]
    )
    #expect(result.markerPostNo == 150)
}

@Test func userRefresh_noNewPosts_markerCleared() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 200,
        postNosAfter: [50, 100, 150, 200]
    )
    #expect(result.markerPostNo == nil)
}

@Test func userRefresh_threadWasEmpty_markerCleared() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: nil,
        postNosAfter: [1, 2, 3]
    )
    #expect(result.markerPostNo == nil)
}

@Test func userRefresh_emptyAfterRefresh_markerCleared() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 100,
        postNosAfter: []
    )
    #expect(result.markerPostNo == nil)
}

@Test func userRefresh_singleNewPost() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 5,
        postNosAfter: [1, 2, 3, 4, 5, 6]
    )
    #expect(result.markerPostNo == 6)
}

@Test func userRefresh_manyNewPosts_markerAtFirst() {
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 10,
        postNosAfter: [1, 5, 10, 15, 20, 25, 30]
    )
    #expect(result.markerPostNo == 15)
}

// MARK: - readStateAfterUserRefresh

@Test func userRefreshReadState_withPosts_marksAllRead() {
    let update = ThreadRefreshLogic.readStateAfterUserRefresh(
        postNosAfter: [10, 20, 30]
    )
    #expect(update?.lastReadPostNo == 30)
    #expect(update?.lastSeenPostNo == 30)
    #expect(update?.newReplyCount == 0)
}

@Test func userRefreshReadState_noPosts_returnsNil() {
    let update = ThreadRefreshLogic.readStateAfterUserRefresh(postNosAfter: [])
    #expect(update == nil)
}

// MARK: - autoRefreshUpdate

@Test func autoRefresh_noExistingMarker_placesMarkerAtFirstUnread() {
    let update = ThreadRefreshLogic.autoRefreshUpdate(
        currentMarkerPostNo: nil,
        lastReadPostNo: 100,
        lastSeenPostNo: 100,
        postNosAfter: [50, 100, 150, 200]
    )
    #expect(update?.markerPostNo == 150)
    #expect(update?.lastSeenPostNo == 200)
    #expect(update?.newReplyCount == 2) // 150 and 200 are > lastSeenPostNo=100
}

@Test func autoRefresh_existingMarker_keepsStable() {
    let update = ThreadRefreshLogic.autoRefreshUpdate(
        currentMarkerPostNo: 150,
        lastReadPostNo: 100,
        lastSeenPostNo: 200,
        postNosAfter: [50, 100, 150, 200, 250, 300]
    )
    // Marker stays at 150 (doesn't jump)
    #expect(update?.markerPostNo == 150)
    #expect(update?.lastSeenPostNo == 300)
    #expect(update?.newReplyCount == 2) // 250 and 300 are > lastSeenPostNo=200
}

@Test func autoRefresh_noNewPosts_countsZero() {
    let update = ThreadRefreshLogic.autoRefreshUpdate(
        currentMarkerPostNo: nil,
        lastReadPostNo: 300,
        lastSeenPostNo: 300,
        postNosAfter: [50, 100, 150, 200, 250, 300]
    )
    #expect(update?.markerPostNo == nil)
    #expect(update?.newReplyCount == 0)
}

@Test func autoRefresh_emptyPosts_returnsNil() {
    let update = ThreadRefreshLogic.autoRefreshUpdate(
        currentMarkerPostNo: nil,
        lastReadPostNo: 100,
        lastSeenPostNo: 100,
        postNosAfter: []
    )
    #expect(update == nil)
}

// MARK: - markerOnInitialLoad

@Test func initialLoad_withUnreadPosts_markerAtFirstUnread() {
    let result = ThreadRefreshLogic.markerOnInitialLoad(
        lastReadPostNo: 100,
        postNos: [50, 100, 150, 200]
    )
    #expect(result.markerPostNo == 150)
}

@Test func initialLoad_allPostsRead_noMarker() {
    let result = ThreadRefreshLogic.markerOnInitialLoad(
        lastReadPostNo: 200,
        postNos: [50, 100, 150, 200]
    )
    #expect(result.markerPostNo == nil)
}

@Test func initialLoad_notWatched_noMarker() {
    let result = ThreadRefreshLogic.markerOnInitialLoad(
        lastReadPostNo: nil,
        postNos: [50, 100, 150, 200]
    )
    #expect(result.markerPostNo == nil)
}

@Test func initialLoad_emptyThread_noMarker() {
    let result = ThreadRefreshLogic.markerOnInitialLoad(
        lastReadPostNo: 100,
        postNos: []
    )
    #expect(result.markerPostNo == nil)
}

// MARK: - readStateAfterScroll

@Test func scroll_highestVisibleAdvancesRead_markerMoves() {
    let result = ThreadRefreshLogic.readStateAfterScroll(
        visiblePosts: Set([100, 150]),
        allPostNos: [50, 100, 150, 200, 250],
        currentLastReadPostNo: 50
    )
    #expect(result?.newLastReadPostNo == 150)
    #expect(result?.markerPostNo == 200)
}

@Test func scroll_allPostsVisible_markerCleared() {
    let result = ThreadRefreshLogic.readStateAfterScroll(
        visiblePosts: Set([200, 250]),
        allPostNos: [50, 100, 150, 200, 250],
        currentLastReadPostNo: 50
    )
    #expect(result?.newLastReadPostNo == 250)
    #expect(result?.markerPostNo == nil) // no posts after 250
}

@Test func scroll_noAdvanceBeyondCurrentRead_returnsNil() {
    let result = ThreadRefreshLogic.readStateAfterScroll(
        visiblePosts: Set([50, 100]),
        allPostNos: [50, 100, 150, 200],
        currentLastReadPostNo: 100
    )
    #expect(result == nil) // highest visible (100) is not > currentLastReadPostNo (100)
}

@Test func scroll_emptyVisiblePosts_returnsNil() {
    let result = ThreadRefreshLogic.readStateAfterScroll(
        visiblePosts: Set(),
        allPostNos: [50, 100, 150],
        currentLastReadPostNo: 0
    )
    #expect(result == nil)
}

// MARK: - Regression: the bug we just fixed

@Test func userRefresh_unwatchedThread_markerStillShows() {
    // This is the exact scenario that was broken:
    // User opens an unwatched thread, taps refresh, new posts arrive.
    // The marker logic must work independently of watch status.
    //
    // The old code had a `guard let watched` that returned early,
    // skipping the marker logic entirely for unwatched threads.
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 500,
        postNosAfter: [100, 200, 300, 400, 500, 600, 700]
    )
    #expect(result.markerPostNo == 600)
}

@Test func userRefresh_unwatchedThread_noNewPosts_markerCleared() {
    // Regression complement: unwatched thread, no new posts after refresh.
    let result = ThreadRefreshLogic.markerAfterUserRefresh(
        lastPostNoBefore: 700,
        postNosAfter: [100, 200, 300, 400, 500, 600, 700]
    )
    #expect(result.markerPostNo == nil)
}
