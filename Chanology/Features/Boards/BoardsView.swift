import SwiftUI

struct BoardsView: View {
    @State private var service = ForegroundRefreshService.shared

    var body: some View {
        Group {
            if service.boardsLoading && service.boards.isEmpty {
                ProgressView("Loading boards…")
            } else {
                List {
                    ForEach(service.workSafeBoards) { board in
                        NavigationLink(value: board) {
                            BoardRow(board: board)
                        }
                    }
                    Section("NSFW") {
                        ForEach(service.nsfwBoards) { board in
                            NavigationLink(value: board) {
                                BoardRow(board: board)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Boards")
        .navigationDestination(for: Board.self) { board in
            CatalogView(board: board)
        }
        .task { await service.fetchBoards() }
        .refreshable { await service.fetchBoards() }
        .alert("Error", isPresented: .constant(service.boardsError != nil)) {
            Button("OK") { service.boardsError = nil }
        } message: {
            Text(service.boardsError?.localizedDescription ?? "")
        }
    }
}

struct BoardRow: View {
    let board: Board
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("/\(board.board)/")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(board.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

private let previewBoards: [Board] = [
    Board(board: "g", title: "Technology", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil),
    Board(board: "a", title: "Anime & Manga", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil),
    Board(board: "b", title: "Random", wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil),
]

#Preview("Boards") {
    NavigationStack {
        BoardsView()
    }
}

#Preview("BoardRow") {
    List(previewBoards) { board in
        BoardRow(board: board)
    }
}
