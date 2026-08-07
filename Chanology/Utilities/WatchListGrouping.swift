import Foundation

/// Groups watched threads by board for `WatchListView`, ordering work-safe boards
/// before NSFW ones and sorting alphabetically within each tier.
enum WatchListGrouping {
    struct BoardGroup {
        let board: String
        let isWorkSafe: Bool
        let threads: [WatchedThread]
    }

    static func grouped(_ threads: [WatchedThread], boards: [Board]) -> [BoardGroup] {
        let workSafeByBoard = Dictionary(uniqueKeysWithValues: boards.map { ($0.board, $0.isWorkSafe) })

        return Dictionary(grouping: threads, by: \.board)
            .map { board, threads in
                BoardGroup(
                    board: board,
                    isWorkSafe: workSafeByBoard[board] ?? true,
                    threads: threads.sorted {
                        $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending
                    }
                )
            }
            .sorted {
                if $0.isWorkSafe != $1.isWorkSafe { return $0.isWorkSafe && !$1.isWorkSafe }
                return $0.board.localizedCaseInsensitiveCompare($1.board) == .orderedAscending
            }
    }
}
