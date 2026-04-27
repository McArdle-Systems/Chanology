import SwiftUI

struct BoardsView: View {
    @State private var service = ForegroundRefreshService.shared
    @State private var showingSettings = false
    @AppStorage("showNSFWBoards") private var showNSFWBoards: Bool = false

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
                    if showNSFWBoards {
                        Section("NSFW") {
                            ForEach(service.nsfwBoards) { board in
                                NavigationLink(value: board) {
                                    BoardRow(board: board)
                                }
                            }
                        }
                    } else {
                        Section {
                        } footer: {
                            Text("NSFW boards are hidden. Tap ⚙ to enable them.")
                                .frame(maxWidth: .infinity, alignment: .center)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("showNSFWBoards") private var showNSFWBoards: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("Show NSFW Boards", isOn: $showNSFWBoards)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

private let previewBoards: [Board] = [
    Board(board: "g", title: "Technology", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil, boardFlags: nil),
    Board(board: "a", title: "Anime & Manga", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil, boardFlags: nil),
    Board(board: "b", title: "Random", wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil, boardFlags: nil),
]

#Preview("Boards — NSFW hidden") {
    let defaults = UserDefaults(suiteName: "preview.nsfw.hidden")!
    defaults.set(false, forKey: "showNSFWBoards")
    ForegroundRefreshService.shared.boards = previewBoards
    return NavigationStack {
        BoardsView()
    }
    .defaultAppStorage(defaults)
}

#Preview("Boards — NSFW shown") {
    let defaults = UserDefaults(suiteName: "preview.nsfw.shown")!
    defaults.set(true, forKey: "showNSFWBoards")
    ForegroundRefreshService.shared.boards = previewBoards
    return NavigationStack {
        BoardsView()
    }
    .defaultAppStorage(defaults)
}

#Preview("BoardRow") {
    List(previewBoards) { board in
        BoardRow(board: board)
    }
}
