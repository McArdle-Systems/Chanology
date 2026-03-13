import SwiftUI
import SwiftData

struct ThreadView: View {
    let board: String
    let threadNo: Int
    let subject: String

    @State private var vm: ThreadViewModel
    @Query private var watchedThreads: [WatchedThread]
    @Environment(\.modelContext) private var modelContext

    init(board: String, threadNo: Int, subject: String) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        _vm = State(initialValue: ThreadViewModel(board: board, threadNo: threadNo))
    }

    fileprivate init(board: String, threadNo: Int, subject: String, mockPosts: [Post]) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        _vm = State(initialValue: ThreadViewModel(board: board, threadNo: threadNo, mockPosts: mockPosts))
    }

    private var isWatched: Bool {
        watchedThreads.contains { $0.board == board && $0.threadNo == threadNo }
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.posts.isEmpty {
                ProgressView("Loading thread…")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(vm.posts) { post in
                                PostView(post: post)
                                    .id(post.no)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .onChange(of: vm.posts.count) { _, _ in
                        // Scroll to bottom on new posts
                    }
                }
            }
        }
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Text(subject)
            Button("Copy Title", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = subject
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleWatch()
                } label: {
                    Image(systemName: isWatched ? "bell.fill" : "bell")
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
    }

    private func toggleWatch() {
        if let existing = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }) {
            modelContext.delete(existing)
        } else {
            let watched = WatchedThread(
                board: board,
                threadNo: threadNo,
                subject: subject,
                lastSeenPostNo: vm.posts.last?.no ?? 0
            )
            modelContext.insert(watched)
        }
    }
}

struct PostView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Text(post.name ?? "Anonymous")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                if let trip = post.trip {
                    Text(trip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let id = post.id {
                    Text("ID:\(id)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.5), in: Capsule())
                }
                Spacer()
                Text("No.\(post.no)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Image
            if let url = post.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    if let thumbURL = post.thumbnailURL {
                        AsyncImage(url: thumbURL) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            Color.secondary.opacity(0.2)
                                .frame(height: 120)
                        }
                    }
                }
                .frame(maxWidth: 260)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Comment — rendered with full HTML (greentext, quote links, entities, etc.)
            if let html = post.com, !html.isEmpty {
                Text(PostHTMLRenderer.render(html))
                    .font(.body)
            }

            Text(post.now)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

private func mockPost(
    no: Int = 99999,
    com: String = ##"<span class="quote">&gt;be me</span><br>&gt;write Swift code all day<br><a href="#p12344" class="quotelink">&gt;&gt;12344</a><br>genuinely enjoying it &#039;desu"##,
    id: String? = "xKz9aB",
    resto: Int = 0,
    sub: String? = "Swift is clearly the best and any other opinion is wrong."
) -> Post {
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": no, "now": "01/01/25(Wed)12:30:00",
        "name": "Anonymous", "id": id as Any,
        "com": com, "resto": resto
    ] as [String: Any])
    var p = try! JSONDecoder().decode(Post.self, from: data)
    p._board = "g"
    return p
}

#Preview("Thread") {
    NavigationStack {
        ThreadView(
            board: "g",
            threadNo: 12345,
            subject: "Post your desktop / tech setups",
            mockPosts: [
                mockPost(no: 12345, com: "Post your desktops and rate others. I&#039;ll start.", resto: 0, sub: "Some subject"),
                mockPost(no: 12346, com: ##"<span class="quote">&gt;be me</span><br>&gt;write Swift code all day<br><a href="#p12345" class="quotelink">&gt;&gt;12345</a><br>genuinely enjoying it &#039;desu"##, resto: 12345),
                mockPost(no: 12347, com: "Anyone else think Rust is overrated? I&#039;ve been writing C for 20 years and never had memory issues.", id: nil, resto: 12345),
            ]
        )
    }
    .modelContainer(for: WatchedThread.self, inMemory: true)
}

#Preview("Post — greentext") {
    PostView(post: mockPost())
        .padding()
}

#Preview("Post — plain") {
    PostView(post: mockPost(
        no: 11111,
        com: "Anyone else think Rust is overrated? I&#039;ve been writing C for 20 years and never had memory issues.",
        id: nil,
        resto: 99999
    ))
    .padding()
}

@Observable
@MainActor
class ThreadViewModel {
    let board: String
    let threadNo: Int
    var posts: [Post] = []
    var isLoading = false
    var error: Error?

    init(board: String, threadNo: Int) {
        self.board = board
        self.threadNo = threadNo
    }

    init(board: String, threadNo: Int, mockPosts: [Post]) {
        self.board = board
        self.threadNo = threadNo
        self.posts = mockPosts
    }

    func load() async {
        guard posts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await ChanAPI.shared.thread(board: board, no: threadNo)
        } catch {
            self.error = error
        }
    }
}
