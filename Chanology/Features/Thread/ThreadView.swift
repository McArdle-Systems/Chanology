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

    let scrollToLastRead: Bool

    @State private var vm: ThreadViewModel
    @State private var expandedImageURL: URL?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var crossThreadTarget: CrossThreadTarget?
    @State private var highlightedPostNo: Int?
    @State private var newRepliesMarkerPostNo: Int?
    @State private var replyMap: [Int: [Int]] = [:]
    @State private var selectedQuotes: [Int] = []
    @State private var showCompose = false
    @State private var showLogin = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var visiblePosts: Set<Int> = []  // Track which posts are currently visible
    @Query private var watchedThreads: [WatchedThread]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    init(board: String, threadNo: Int, subject: String, scrollToLastRead: Bool = false) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        self.scrollToLastRead = scrollToLastRead
        _vm = State(initialValue: ThreadViewModel(board: board, threadNo: threadNo))
    }

    fileprivate init(board: String, threadNo: Int, subject: String, mockPosts: [Post]) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        self.scrollToLastRead = false
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
                                if post.no == newRepliesMarkerPostNo {
                                    NewRepliesMarker()
                                        .id("new-replies-marker")
                                }
                                postRow(post)
                                    .onAppear {
                                        visiblePosts.insert(post.no)
                                    }
                                    .onDisappear {
                                        visiblePosts.remove(post.no)
                                    }
                            }

                            // Bottom refresh
                            Button {
                                Task {
                                    await refreshThread(userInitiated: true)
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
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
        .task {
            // Capture the read boundary before loading new posts
            let lastRead = watchedThreads
                .first(where: { $0.board == board && $0.threadNo == threadNo })?
                .lastReadPostNo

            await vm.load()
            replyMap = ReplyMapBuilder.build(from: vm.posts)

            // Find the first post after the read boundary
            if let lastRead, let firstNew = vm.posts.first(where: { $0.no > lastRead }) {
                newRepliesMarkerPostNo = firstNew.no
                if scrollToLastRead {
                    // Small delay for LazyVStack to lay out
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation {
                        scrollProxy?.scrollTo("new-replies-marker", anchor: .top)
                    }
                }
            }
            
            // Start auto-refresh if this thread is watched
            if isWatched {
                startAutoRefresh()
            }
        }
        .refreshable {
            await refreshThread(userInitiated: true)
        }
        .onDisappear { 
            markVisiblePostsAsRead()
            stopAutoRefresh()
        }
        .onChange(of: isWatched) { _, watched in
            if watched {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                markVisiblePostsAsRead()
            }
        }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
        .overlay(alignment: .bottomTrailing) {
            composeButton
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(
                board: board,
                threadNo: threadNo,
                selectedQuotes: selectedQuotes,
                onPosted: { newPostNo in
                    selectedQuotes.removeAll()
                    // Track our post for reply highlighting
                    if let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }) {
                        watched.myPostNumbers.append(newPostNo)
                    }
                    // Refresh thread to show new post (without triggering the "new posts" marker)
                    Task {
                        await vm.load(refresh: true)
                        replyMap = ReplyMapBuilder.build(from: vm.posts)
                        // Don't show marker for our own posts
                    }
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

    @ViewBuilder
    private var composeButton: some View {
        Button {
            if ChanPostAPI.shared.isAuthenticated {
                showCompose = true
            } else {
                showLogin = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                if !selectedQuotes.isEmpty {
                    Text("\(selectedQuotes.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .font(.title3)
            .padding()
            .background(.ultraThinMaterial, in: Circle())
            .shadow(radius: 4)
        }
        .padding()
    }

    /// Whether the given post quotes one of the user's own posts.
    private func isReplyToUser(_ post: Post) -> Bool {
        guard let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }),
              !watched.myPostNumbers.isEmpty else { return false }
        let quoted = ReplyMapBuilder.quotedPosts(in: post)
        return quoted.contains(where: watched.myPostNumbers.contains)
    }

    @ViewBuilder
    private func postRow(_ post: Post) -> some View {
        let isHighlighted = highlightedPostNo == post.no
        let isUserReply = isReplyToUser(post)
        PostView(
            post: post,
            replyingPosts: replyMap[post.no] ?? [],
            isQuoteSelected: selectedQuotes.contains(post.no),
            onImageTap: { url in expandedImageURL = url },
            onPostNumberTap: { postNo in
                if let idx = selectedQuotes.firstIndex(of: postNo) {
                    selectedQuotes.remove(at: idx)
                } else {
                    selectedQuotes.append(postNo)
                }
            }
        )
        .id(post.no)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isUserReply ? Color.orange : Color.accentColor, lineWidth: isUserReply ? 1.5 : 2)
                .shadow(color: isUserReply ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.6),
                        radius: isHighlighted ? 8 : (isUserReply ? 6 : 0))
                .opacity(isHighlighted || isUserReply ? 1 : 0)
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

    /// Marks the currently visible posts as read and updates the marker
    private func markVisiblePostsAsRead() {
        guard let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }),
              !visiblePosts.isEmpty else { return }
        
        // Find the highest visible post number
        let highestVisible = visiblePosts.max() ?? 0
        
        // Update lastReadPostNo to the highest visible post
        if highestVisible > watched.lastReadPostNo {
            watched.lastReadPostNo = highestVisible
            watched.lastChecked = Date()
            
            // Update the marker to the first post after what we've read
            if let firstNew = vm.posts.first(where: { $0.no > highestVisible }) {
                newRepliesMarkerPostNo = firstNew.no
            } else {
                // No new posts, clear marker
                newRepliesMarkerPostNo = nil
                watched.newReplyCount = 0
            }
        }
        
        // Always update lastSeenPostNo to the absolute last post
        if let lastPost = vm.posts.last {
            watched.lastSeenPostNo = lastPost.no
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
    
    /// Shared refresh logic
    /// - Parameter userInitiated: If true, marks everything as read and clears the marker
    private func refreshThread(userInitiated: Bool = false) async {
        // Capture the last known post number before loading
        let lastPostNoBefore = vm.posts.last?.no
        
        await vm.load(refresh: true)
        replyMap = ReplyMapBuilder.build(from: vm.posts)
        
        guard let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }) else {
            return
        }
        
        if userInitiated {
            // Place the marker at the first post that is new since the last load
            if let lastPostNoBefore, let firstNew = vm.posts.first(where: { $0.no > lastPostNoBefore }) {
                newRepliesMarkerPostNo = firstNew.no
            }
            // Mark everything as read since the user is actively checking
            if let lastPost = vm.posts.last {
                watched.lastReadPostNo = lastPost.no
                watched.lastSeenPostNo = lastPost.no
                watched.newReplyCount = 0
                watched.lastChecked = Date()
            }
        } else {
            // Auto-refresh: keep marker stable, only add it if it doesn't exist
            if newRepliesMarkerPostNo == nil,
               let firstNew = vm.posts.first(where: { $0.no > watched.lastReadPostNo }) {
                newRepliesMarkerPostNo = firstNew.no
            }
            
            // Update lastSeenPostNo and newReplyCount
            if let lastPost = vm.posts.last {
                let newPostCount = vm.posts.filter { $0.no > watched.lastSeenPostNo }.count
                watched.lastSeenPostNo = lastPost.no
                watched.newReplyCount = newPostCount
                watched.lastChecked = Date()
            }
        }
    }
    
    /// Start auto-refresh timer (30 seconds interval for open watched threads)
    private func startAutoRefresh() {
        stopAutoRefresh() // Cancel any existing task
        
        autoRefreshTask = Task {
            while !Task.isCancelled {
                // Wait 30 seconds
                try? await Task.sleep(for: .seconds(30))
                
                guard !Task.isCancelled else { break }
                
                // Perform background refresh (not user-initiated, so marker stays stable)
                await refreshThread(userInitiated: false)
            }
        }
    }
    
    /// Stop auto-refresh timer
    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}

struct PostView: View {
    let post: Post
    var replyingPosts: [Int] = []
    var isQuoteSelected: Bool = false
    var onImageTap: ((URL) -> Void)?
    var onPostNumberTap: ((Int) -> Void)?

    @Environment(\.openURL) private var openURL

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
                // Country flag (emoji)
                if let emoji = post.countryEmoji {
                    Text(emoji)
                        .font(.caption)
                        .help(post.countryName ?? "")
                }
                // Board-specific meme flag (image)
                if let flagURL = post.boardFlagURL {
                    AsyncImage(url: flagURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            // Show flag name text if image fails to load
                            Text(post.flagName ?? post.boardFlag ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                                .controlSize(.mini)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 12)
                    .help(post.flagName ?? "")
                }
                Spacer()
                // Tappable post number for quoting
                Button {
                    onPostNumberTap?(post.no)
                } label: {
                    HStack(spacing: 3) {
                        if isQuoteSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(verbatim: "No.\(post.no)")
                            .font(.caption2)
                            .foregroundStyle(isQuoteSelected ? Color.accentColor : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
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

            // Reply count pills
            if !replyingPosts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(replyingPosts, id: \.self) { replyNo in
                        Button {
                            if let url = URL(string: "chanology://post/\(replyNo)") {
                                openURL(url)
                            }
                        } label: {
                            Text(verbatim: ">>\(replyNo)")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - New Replies Marker

struct NewRepliesMarker: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1)
            Text("New Replies")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .layoutPriority(1)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

            imageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            closeButton
                .padding()
        }
        .onTapGesture { dismiss() }
    }
    
    private var imageView: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2, perform: handleDoubleTap)
        } placeholder: {
            ProgressView()
                .tint(.white)
        }
    }
    
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .gray.opacity(0.6))
        }
    }
    
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = lastScale * value.magnification
            }
            .onEnded { value in
                lastScale = max(1.0, lastScale * value.magnification)
                withAnimation {
                    scale = lastScale
                    if scale <= 1.0 {
                        resetZoom()
                    }
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private func handleDoubleTap() {
        withAnimation {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
    
    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Previews

private func mockPost(
    no: Int = 99999,
    com: String = ##"<span class="quote">&gt;be me</span><br>&gt;write Swift code all day<br><a href="#p12344" class="quotelink">&gt;&gt;12344</a><br>genuinely enjoying it &#039;desu"##,
    id: String? = "xKz9aB",
    resto: Int = 0,
    sub: String? = nil,
    // 2 letter country
    country: String? = nil,
    // full country name
    countryName: String? = nil,
    // meme flag 2 letter code
    boardFlag: String? = nil,
    // meme flag display name
    flagName: String? = nil
) -> Post {
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": no, "now": "01/01/25(Wed)12:30:00",
        "name": "Anonymous", "id": id as Any,
        "com": com, "resto": resto, "sub": sub as Any,
        "country": country as Any, "country_name": countryName as Any,
        "board_flag": boardFlag as Any, "flag_name": flagName as Any
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

#Preview("New Replies Marker") {
    VStack(spacing: 0) {
        PostView(post: mockPost(no: 11111, com: "Old post above the marker", resto: 99999))
        Divider().padding(.leading, 16)
        NewRepliesMarker()
        PostView(post: mockPost(no: 22222, com: "New post below the marker", resto: 99999))
    }
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

#Preview("Post — country flag") {
    PostView(post: mockPost(
        no: 11111,
        com: "Anyone else think Rust is overrated? I&#039;ve been writing C for 20 years and never had memory issues.",
        id: nil,
        resto: 99999,
        country: "US",
        countryName: "United States"
        
    ))
    .padding()
}

#Preview("Post — meme flag") {
    PostView(post: mockPost(
        no: 11111,
        com: "Anyone else think Rust is overrated? I&#039;ve been writing C for 20 years and never had memory issues.",
        id: nil,
        resto: 99999,
        boardFlag: "AC",
        flagName: "Anarcho-Capitalist"
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

    func load(refresh: Bool = false) async {
        guard posts.isEmpty || refresh else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await ChanAPI.shared.thread(board: board, no: threadNo)
        } catch {
            self.error = error
        }
    }
}
