import SwiftUI
import SwiftData

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct CrossThreadTarget: Hashable {
    let board: String
    let threadNo: Int
}

struct ThreadView: View {
    let board: String
    let threadNo: Int
    let subject: String

    @State private var vm: ThreadViewModel
    @State private var expandedImageURL: URL?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var crossThreadTarget: CrossThreadTarget?
    @State private var highlightedPostNo: Int?
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
                                postRow(post)
                            }
                        }
                    }
                    .onAppear { scrollProxy = proxy }
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
        .fullScreenCover(item: $expandedImageURL) { url in
            ExpandedImageView(url: url)
        }
        .navigationDestination(item: $crossThreadTarget) { target in
            ThreadView(board: target.board, threadNo: target.threadNo, subject: "Thread #\(target.threadNo)")
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
    }

    @ViewBuilder
    private func postRow(_ post: Post) -> some View {
        let isHighlighted = highlightedPostNo == post.no
        PostView(post: post, onImageTap: { url in
            expandedImageURL = url
        })
        .id(post.no)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .shadow(color: Color.accentColor.opacity(0.6), radius: isHighlighted ? 8 : 0)
                .opacity(isHighlighted ? 1 : 0)
                .padding(.horizontal, 4)
        )
        .environment(\.openURL, OpenURLAction { url in
            return handleLink(url)
        })
        Divider().padding(.leading, 16)
    }

    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "chanology" else { return .systemAction }

        let parts = url.pathComponents.filter { $0 != "/" }

        switch url.host() {
        case "post":
            // Intra-thread scroll: chanology://post/123456
            if let postNo = Int(url.lastPathComponent) {
                withAnimation {
                    scrollProxy?.scrollTo(postNo, anchor: .top)
                }
                // Animate highlight after scroll settles
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.easeIn(duration: 0.3)) {
                        highlightedPostNo = postNo
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeOut(duration: 0.5)) {
                        highlightedPostNo = nil
                    }
                }
            }
            return .handled
        case "thread":
            // Cross-board thread: chanology://thread/g/123456
            if parts.count >= 2, let threadNo = Int(parts[1]) {
                crossThreadTarget = CrossThreadTarget(board: parts[0], threadNo: threadNo)
            }
            return .handled
        case "board":
            // Cross-board link: chanology://board/g
            // Board navigation requires the Board model; for now open the thread list isn't possible
            // without fetching the board metadata. We'll skip this gracefully.
            return .discarded
        default:
            return .systemAction
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
    var onImageTap: ((URL) -> Void)?

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
                if let id = post.posterID {
                    Text("ID:\(id)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.5), in: Capsule())
                }
                Spacer()
                Text(verbatim: "No.\(post.no)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Image — tap to expand
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
                .onTapGesture { onImageTap?(url) }
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

// MARK: - Expanded Image View

struct ExpandedImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { value in
                                lastScale = max(1.0, lastScale * value.magnification)
                                withAnimation {
                                    scale = lastScale
                                    if scale <= 1.0 {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { value in
                                        lastOffset = offset
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray.opacity(0.6))
            }
            .padding()
        }
        .onTapGesture { dismiss() }
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
