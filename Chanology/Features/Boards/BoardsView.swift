import SwiftUI

// MARK: - Starred Boards Store

@Observable
@MainActor
final class StarredBoardsStore {
    static let shared = StarredBoardsStore()

    var boardIDs: Set<String>

    private init() {
        boardIDs = Set(UserDefaults.standard.stringArray(forKey: "starredBoards") ?? [])
    }

    func toggle(_ boardID: String) {
        if boardIDs.contains(boardID) { boardIDs.remove(boardID) } else { boardIDs.insert(boardID) }
        UserDefaults.standard.set(Array(boardIDs), forKey: "starredBoards")
    }

    func isStarred(_ boardID: String) -> Bool { boardIDs.contains(boardID) }
}

// MARK: - Boards View

struct BoardsView: View {
    @State private var service = ForegroundRefreshService.shared
    @State private var starredStore = StarredBoardsStore.shared
    @State private var showingSettings = false
    @AppStorage("showNSFWBoards") private var showNSFWBoards: Bool = false

    private var starredBoards: [Board] {
        let all = service.workSafeBoards + (showNSFWBoards ? service.nsfwBoards : [])
        return all.filter { starredStore.isStarred($0.board) }
    }

    var body: some View {
        Group {
            if service.boardsLoading && service.boards.isEmpty {
                ProgressView("Loading boards…")
            } else {
                List {
                    if !starredBoards.isEmpty {
                        Section("Starred") {
                            ForEach(starredBoards) { board in
                                NavigationLink(value: board) {
                                    BoardRow(board: board)
                                }
                                .swipeActions(edge: .trailing) { starAction(for: board) }
                            }
                        }
                    }

                    ForEach(service.workSafeBoards) { board in
                        NavigationLink(value: board) {
                            BoardRow(board: board)
                        }
                        .swipeActions(edge: .trailing) { starAction(for: board) }
                    }

                    if showNSFWBoards {
                        Section("NSFW") {
                            ForEach(service.nsfwBoards) { board in
                                NavigationLink(value: board) {
                                    BoardRow(board: board)
                                }
                                .swipeActions(edge: .trailing) { starAction(for: board) }
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

    @ViewBuilder
    private func starAction(for board: Board) -> some View {
        let starred = starredStore.isStarred(board.board)
        Button { starredStore.toggle(board.board) } label: {
            Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star")
        }
        .tint(.yellow)
    }
}

// MARK: - Board Row

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
    @AppStorage("notificationSoundEnabled") private var notificationSoundEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("Show NSFW Boards", isOn: $showNSFWBoards)
                }
                Section("Notifications") {
                    Toggle("Play Sound", isOn: $notificationSoundEnabled)
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

#Preview("Boards — starred") {
    let defaults = UserDefaults(suiteName: "preview.starred")!
    defaults.set(false, forKey: "showNSFWBoards")
    ForegroundRefreshService.shared.boards = previewBoards
    StarredBoardsStore.shared.boardIDs = ["g"]
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
