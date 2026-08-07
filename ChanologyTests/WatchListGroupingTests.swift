import Testing
import Foundation
@testable import Chanology

private func board(_ code: String, workSafe: Bool) -> Board {
    Board(board: code, title: code, wsBoard: workSafe ? 1 : 0, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil)
}

private func watched(_ board: String, subject: String) -> WatchedThread {
    WatchedThread(board: board, threadNo: Int.random(in: 1...999_999), subject: subject, lastSeenPostNo: 0)
}

@Test func grouping_groupsThreadsByBoard() {
    let threads = [
        watched("g", subject: "Tech thread"),
        watched("a", subject: "Anime thread"),
        watched("g", subject: "Another tech thread"),
    ]
    let groups = WatchListGrouping.grouped(threads, boards: [])
    #expect(groups.map(\.board).sorted() == ["a", "g"])
    #expect(groups.first(where: { $0.board == "g" })?.threads.count == 2)
}

@Test func grouping_sortsBoardsWorkSafeFirstThenAlphabetically() {
    let threads = [
        watched("v", subject: "Video games"),
        watched("b", subject: "Random"),
        watched("a", subject: "Anime"),
    ]
    let boards = [board("v", workSafe: true), board("b", workSafe: false), board("a", workSafe: true)]
    let groups = WatchListGrouping.grouped(threads, boards: boards)
    #expect(groups.map(\.board) == ["a", "v", "b"])
}

@Test func grouping_unknownBoardDefaultsToWorkSafe() {
    let threads = [watched("xyz", subject: "Mystery board")]
    let groups = WatchListGrouping.grouped(threads, boards: [])
    #expect(groups.first?.isWorkSafe == true)
}

@Test func grouping_sortsThreadsWithinGroupAlphabeticallyBySubject() {
    let threads = [
        watched("g", subject: "Zebra thread"),
        watched("g", subject: "Apple thread"),
        watched("g", subject: "mango thread"),
    ]
    let groups = WatchListGrouping.grouped(threads, boards: [board("g", workSafe: true)])
    #expect(groups.first?.threads.map(\.subject) == ["Apple thread", "mango thread", "Zebra thread"])
}
