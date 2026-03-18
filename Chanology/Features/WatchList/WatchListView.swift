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
                    ForEach(watchedThreads) { thread in
                        NavigationLink(value: thread) {
                            WatchedThreadRow(thread: thread)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(watchedThreads[index])
                        }
                    }
                }
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
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let ctx = modelContext
                    Task { @MainActor in
                        await BackgroundRefreshHandler.performRefresh(using: ctx)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            #endif
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
    container.mainContext.insert(t1)
    container.mainContext.insert(t2)

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
            HStack {
                Text("/\(thread.board)/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if thread.newReplyCount > 0 {
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
