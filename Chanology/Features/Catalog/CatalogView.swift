import SwiftUI
import SwiftData

struct NewThreadTarget: Hashable {
    let threadNo: Int
    let subject: String
}

struct CatalogView: View {
    let board: Board
    @State private var service = ForegroundRefreshService.shared
    @State private var searchText: String = ""
    @State private var sortOrder: CatalogSortOrder = .bumpOrder
    @State private var showCompose = false
    @State private var showLogin = false
    @State private var isAuthenticating = false
    @State private var navigateToNewThread: NewThreadTarget?
    @Query private var watchedThreads: [WatchedThread]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("catalogToolbarSide") private var toolbarSide: FloatingToolbarSide = .trailing

    var body: some View {
        Group {
            if service.isCatalogLoading(board: board.board) && service.catalogThreads(board: board.board).isEmpty {
                ProgressView("Loading /\(board.board)/…")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredThreads) { thread in
                            NavigationLink(value: thread) {
                                CatalogThreadRow(
                                    thread: thread,
                                    board: board.board,
                                    isWatched: watchedThreads.contains { $0.board == board.board && $0.threadNo == thread.no }
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle("/\(board.board)/ — \(board.title)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CatalogThread.self) { thread in
            ThreadView(board: board.board, threadNo: thread.no, subject: thread.decodedSubject ?? thread.plainTextComment ?? "Thread")
        }
        .navigationDestination(item: $navigateToNewThread) { target in
            ThreadView(board: board.board, threadNo: target.threadNo, subject: target.subject)
        }
        .searchable(text: $searchText, prompt: "Search threads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(CatalogSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task { await service.fetchCatalog(board: board.board) }
        .refreshable { await service.fetchCatalog(board: board.board) }
        .alert("Error", isPresented: .constant(service.catalogError[board.board] != nil)) {
            Button("OK") { service.catalogError.removeValue(forKey: board.board) }
        } message: {
            Text(service.catalogError[board.board]?.localizedDescription ?? "")
        }
        .overlay {
            FloatingToolbar(actions: floatingToolbarActions, side: $toolbarSide)
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(
                board: board.board,
                mode: .newThread,
                onThreadCreated: { newThreadNo, subject, comment in
                    await handleNewThreadCreated(threadNo: newThreadNo, subject: subject, comment: comment)
                }
            )
        }
        .sheet(isPresented: $showLogin) {
            LoginView(onSuccess: {
                showLogin = false
                showCompose = true
            })
        }
    }

    private var floatingToolbarActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "new-thread",
                icon: isAuthenticating ? "ellipsis" : "square.and.pencil",
                label: "New thread",
                role: .prominent,
                isEnabled: !isAuthenticating,
                action: { triggerNewThread() }
            )
        ]
    }

    private func triggerNewThread() {
        if ChanPostAPI.shared.isAuthenticated {
            showCompose = true
        } else {
            Task {
                isAuthenticating = true
                do {
                    try await ChanPostAPI.shared.reauthenticateIfNeeded()
                    showCompose = true
                } catch {
                    showLogin = true
                }
                isAuthenticating = false
            }
        }
    }

    /// Auto-watch the newly-created thread and navigate to it.
    private func handleNewThreadCreated(threadNo: Int, subject: String, comment: String) async {
        guard threadNo > 0 else { return }
        let title = NewThreadTitleBuilder.title(subject: subject, comment: comment, threadNo: threadNo)
        if !watchedThreads.contains(where: { $0.board == board.board && $0.threadNo == threadNo }) {
            let watched = WatchedThread(
                board: board.board,
                threadNo: threadNo,
                subject: title,
                lastSeenPostNo: threadNo
            )
            modelContext.insert(watched)
        }
        // Refresh catalog so the new OP shows up in the catalog list.
        await service.fetchCatalog(board: board.board)
        navigateToNewThread = NewThreadTarget(threadNo: threadNo, subject: title)
    }

    private var filteredThreads: [CatalogThread] {
        let threads = service.catalogThreads(board: board.board)
        let sorted: [CatalogThread]
        switch sortOrder {
        case .bumpOrder:
            sorted = threads
        case .mostReplies:
            sorted = threads.sorted { $0.replies > $1.replies }
        case .newest:
            sorted = threads.sorted { $0.no > $1.no }
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { thread in
            thread.sub?.localizedCaseInsensitiveContains(searchText) == true ||
            thread.plainTextComment?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
}

struct CatalogThreadRow: View {
    let thread: CatalogThread
    let board: String
    var isWatched: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            if let url = thread.thumbnailURL(board: board) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    if let ratio = thread.imageAspectRatio {
                        Color.secondary.opacity(0.2).frame(width: 80, height: 80 * ratio)
                    } else {
                        Color.secondary.opacity(0.2).frame(width: 80, height: 80)
                    }
                }
                .frame(width: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "text.bubble").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                if let sub = thread.decodedSubject, !sub.isEmpty {
                    Text(sub)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let comment = thread.plainTextComment {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 12) {
                    Label("\(thread.replies)", systemImage: "bubble.right")
                    Label("\(thread.images)", systemImage: "photo")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 4) {
                if (thread.sticky ?? 0) != 0 {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.purple, in: Circle())
                }
                if isWatched {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.red, in: Circle())
                }
            }
            .padding(8)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

private let previewBoard = Board(
    board: "g", title: "Technology",
    wsBoard: 1, perPage: 15, pages: 10,
    maxFilesize: 4194304, maxWebmFilesize: 3145728,
    maxCommentChars: 2000, isArchived: nil, boardFlags: nil
)

private func mockCatalogThread(no: Int = 12345, sub: String? = nil, com: String? = nil, replies: Int = 42, sticky: Bool = false) -> CatalogThread {
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": no, "now": "01/01/25(Wed)12:00:00",
        "sub": sub as Any,
        "com": (com ?? "&gt;be me<br>post tech things<br>get (you)s") as Any,
        "replies": replies, "images": 10, "last_modified": 1735000000,
        "sticky": sticky ? 1 : 0
    ] as [String: Any])
    var t = try! JSONDecoder().decode(CatalogThread.self, from: data)
    t._board = "g"
    return t
}

enum CatalogSortOrder: String, CaseIterable {
    case bumpOrder = "Bump Order"
    case mostReplies = "Most Replies"
    case newest = "Newest Threads"
}

#Preview("Catalog") {
    NavigationStack {
        CatalogView(board: previewBoard)
    }
    .modelContainer(for: WatchedThread.self, inMemory: true)
}

#Preview("CatalogThreadRow — with subject") {
    CatalogThreadRow(
        thread: mockCatalogThread(sub: "What&#039;s your development environment?"),
        board: "g"
    )
    .padding(.vertical, 4)
}

#Preview("CatalogThreadRow — no subject") {
    CatalogThreadRow(
        thread: mockCatalogThread(replies: 1337),
        board: "g"
    )
    .padding(.vertical, 4)
}

#Preview("CatalogThreadRow — watched") {
    CatalogThreadRow(
        thread: mockCatalogThread(sub: "What&#039;s your development environment?", replies: 42),
        board: "g",
        isWatched: true
    )
    .padding(.vertical, 4)
}

#Preview("CatalogThreadRow — sticky") {
    CatalogThreadRow(
        thread: mockCatalogThread(sub: "Welcome to /g/ — READ BEFORE POSTING", replies: 0, sticky: true),
        board: "g"
    )
    .padding(.vertical, 4)
}

#Preview("CatalogThreadRow — sticky + watched") {
    CatalogThreadRow(
        thread: mockCatalogThread(sub: "Welcome to /g/ — READ BEFORE POSTING", replies: 0, sticky: true),
        board: "g",
        isWatched: true
    )
    .padding(.vertical, 4)
}
