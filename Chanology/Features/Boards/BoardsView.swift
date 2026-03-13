import SwiftUI

struct BoardsView: View {
    @State private var vm = BoardsViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.boards.isEmpty {
                ProgressView("Loading boards…")
            } else {
                List {
                    ForEach(vm.workSafeBoards) { board in
                        NavigationLink(value: board) {
                            BoardRow(board: board)
                        }
                    }
                    Section("NSFW") {
                        ForEach(vm.nsfwBoards) { board in
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
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
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

@Observable
@MainActor
class BoardsViewModel {
    var boards: [Board] = []
    var isLoading = false
    var error: Error?

    var workSafeBoards: [Board] { boards.filter(\.isWorkSafe) }
    var nsfwBoards: [Board] { boards.filter { !$0.isWorkSafe } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            boards = try await ChanAPI.shared.boards()
        } catch {
            self.error = error
        }
    }
}
