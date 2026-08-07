import SwiftUI
import SwiftData

struct WatchedThreadTarget: Hashable {
    let board: String
    let threadNo: Int
    let subject: String
}

struct WatchListView: View {
    @Query private var watchedThreads: [WatchedThread]
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = NavigationCoordinator.shared
    @State private var pendingTarget: WatchedThreadTarget?
    @State private var service = ForegroundRefreshService.shared

    private var groupedByBoard: [WatchListGrouping.BoardGroup] {
        WatchListGrouping.grouped(watchedThreads, boards: service.boards)
    }

    var body: some View {
        Group {
            if watchedThreads.isEmpty {
                ContentUnavailableView(
                    "No Watched Threads",
                    systemImage: "bell.slash",
                    description: Text("Tap the bell icon in any thread to watch it for replies.")
                )
            } else {
                List {
                    ForEach(groupedByBoard, id: \.board) { group in
                        Section {
                            ForEach(group.threads) { thread in
                                NavigationLink(value: thread) {
                                    WatchedThreadRow(thread: thread)
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    modelContext.delete(group.threads[index])
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text("/\(group.board)/")
                                if !group.isWorkSafe {
                                    Text("NSFW")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.red, in: Capsule())
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Watching")
        .navigationDestination(for: WatchedThread.self) { thread in
            ThreadView(board: thread.board, threadNo: thread.threadNo, subject: thread.subject, scrollToLastRead: true)
        }
        .navigationDestination(item: $pendingTarget) { target in
            ThreadView(board: target.board, threadNo: target.threadNo, subject: target.subject, scrollToLastRead: true)
        }
        .onChange(of: coordinator.pendingThread?.threadNo) { _, _ in
            consumePendingThread()
        }
        .task {
            // Small delay to let the view finish appearing before navigating
            try? await Task.sleep(for: .milliseconds(300))
            consumePendingThread()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !watchedThreads.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private func consumePendingThread() {
        if let pending = coordinator.pendingThread {
            pendingTarget = WatchedThreadTarget(board: pending.board, threadNo: pending.threadNo, subject: pending.subject)
            coordinator.pendingThread = nil
        }
    }
}

// MARK: - Previews

#Preview("WatchList — empty") {
    NavigationStack { WatchListView() }
        .modelContainer(for: WatchedThread.self, inMemory: true)
}

#Preview("WatchList — with threads") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WatchedThread.self, configurations: config)

    let t1 = WatchedThread(board: "g", threadNo: 12345, subject: "Post your desktop / tech setups", lastSeenPostNo: 200)
    t1.newReplyCount = 7
    let t2 = WatchedThread(board: "a", threadNo: 99999, subject: "Seasonal anime general", lastSeenPostNo: 500)
    t2.newReplyCount = 0
    let t3 = WatchedThread(board: "g", threadNo: 11111, subject: "Old thread that got archived", lastSeenPostNo: 100)
    t3.isClosed = true
    t3.isArchived = true
    let t4 = WatchedThread(board: "b", threadNo: 55555, subject: "Random thread", lastSeenPostNo: 900)
    t4.newReplyCount = 3
    container.mainContext.insert(t1)
    container.mainContext.insert(t2)
    container.mainContext.insert(t3)
    container.mainContext.insert(t4)

    ForegroundRefreshService.shared.boards = [
        Board(board: "g", title: "Technology", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil),
        Board(board: "a", title: "Anime & Manga", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil),
        Board(board: "b", title: "Random", wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil),
    ]

    return NavigationStack { WatchListView() }
        .modelContainer(container)
}

#Preview("WatchedThreadRow — with badge") {
    let thread = WatchedThread(board: "g", threadNo: 1, subject: "Rust vs Go which wins", lastSeenPostNo: 0)
    thread.newReplyCount = 12
    return WatchedThreadRow(thread: thread).padding()
        .modelContainer(for: WatchedThread.self, inMemory: true)
}

struct WatchedThreadRow: View {
    let thread: WatchedThread

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thread.subject)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(thread.isArchived ? .secondary : .primary)
            HStack {
                Text("/\(thread.board)/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if thread.isArchived {
                    Text("Archived")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                } else if thread.newReplyCount > 0 {
                    Text("\(thread.newReplyCount) new")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
