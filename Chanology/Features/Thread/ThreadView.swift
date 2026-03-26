import SwiftUI
import SwiftData
import AVKit
import WebKit

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
    @State private var highlightedPosterID: String?
    @State private var showFullTitle = false
    @State private var showCompose = false
    @State private var showLogin = false
    @State private var showArchivedToast = false
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
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showFullTitle = true
                }
            } label: {
                Label("Show Full Title", systemImage: "text.justify.leading")
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
        .overlay(alignment: .top) {
            if showFullTitle {
                Text(subject)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .shadow(radius: 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.15)) {
                            showFullTitle = false
                        }
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
            // Pre-warm WebKit and AVAudioSession so first video playback is fast
            MediaPlayerPreloader.shared.warmUp()

            // Capture the read boundary before loading new posts
            let lastRead = watchedThreads
                .first(where: { $0.board == board && $0.threadNo == threadNo })?
                .lastReadPostNo

            await vm.load()
            replyMap = ReplyMapBuilder.build(from: vm.posts)

            // Find the first post after the read boundary
            let marker = ThreadRefreshLogic.markerOnInitialLoad(
                lastReadPostNo: lastRead,
                postNos: vm.posts.map(\.no)
            )
            if let postNo = marker.markerPostNo {
                newRepliesMarkerPostNo = postNo
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
        .overlay(alignment: .bottom) {
            if showArchivedToast {
                Text("This thread has been archived and can no longer be replied to.")
                    .font(.subheadline)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .shadow(radius: 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 80)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showArchivedToast)
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

    private var isThreadClosed: Bool {
        guard let op = vm.posts.first else { return false }
        return (op.closed ?? 0) != 0 || (op.archived ?? 0) != 0
    }

    @ViewBuilder
    private var composeButton: some View {
        Button {
            if isThreadClosed {
                showArchivedToast = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showArchivedToast = false
                }
            } else if ChanPostAPI.shared.isAuthenticated {
                showCompose = true
            } else {
                showLogin = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .symbolVariant(isThreadClosed ? .slash : .none)
                if !selectedQuotes.isEmpty && !isThreadClosed {
                    Text("\(selectedQuotes.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .font(.title3)
            .padding()
            .foregroundStyle(isThreadClosed ? .secondary : .primary)
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

    /// The post numbers this user has made in the current thread.
    private var myPostNumbers: [Int] {
        watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo })?.myPostNumbers ?? []
    }

    /// Count of posts per poster ID in this thread.
    private var posterPostCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for post in vm.posts {
            if let id = post.posterID {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    @ViewBuilder
    private func postRow(_ post: Post) -> some View {
        let isHighlighted = highlightedPostNo == post.no
        let isUserReply = isReplyToUser(post)
        let isPosterHighlighted = highlightedPosterID != nil && post.posterID == highlightedPosterID
        PostView(
            post: post,
            replyingPosts: replyMap[post.no] ?? [],
            isQuoteSelected: selectedQuotes.contains(post.no),
            myPostNumbers: myPostNumbers,
            posterPostCounts: posterPostCounts,
            onImageTap: { url in expandedImageURL = url },
            onPostNumberTap: { postNo in
                if let idx = selectedQuotes.firstIndex(of: postNo) {
                    selectedQuotes.remove(at: idx)
                } else {
                    selectedQuotes.append(postNo)
                }
            },
            onPosterIDTap: { posterID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if highlightedPosterID == posterID {
                        highlightedPosterID = nil
                    } else {
                        highlightedPosterID = posterID
                    }
                }
            }
        )
        .id(post.no)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isPosterHighlighted ? Color.yellow :
                    isUserReply ? Color.orange : Color.accentColor,
                    lineWidth: isPosterHighlighted ? 2 : (isUserReply ? 1.5 : 2)
                )
                .shadow(
                    color: isPosterHighlighted ? Color.yellow.opacity(0.5) :
                           isUserReply ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.6),
                    radius: isHighlighted ? 8 : (isPosterHighlighted ? 6 : (isUserReply ? 6 : 0))
                )
                .opacity(isHighlighted || isUserReply || isPosterHighlighted ? 1 : 0)
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
        
        if let result = ThreadRefreshLogic.readStateAfterScroll(
            visiblePosts: visiblePosts,
            allPostNos: vm.posts.map(\.no),
            currentLastReadPostNo: watched.lastReadPostNo
        ) {
            watched.lastReadPostNo = result.newLastReadPostNo
            watched.lastChecked = Date()
            newRepliesMarkerPostNo = result.markerPostNo
            if result.markerPostNo == nil {
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
        
        let postNos = vm.posts.map(\.no)
        
        // Place or clear the new-replies marker for any user-initiated refresh,
        // regardless of whether the thread is watched.
        if userInitiated {
            let marker = ThreadRefreshLogic.markerAfterUserRefresh(
                lastPostNoBefore: lastPostNoBefore,
                postNosAfter: postNos
            )
            newRepliesMarkerPostNo = marker.markerPostNo
        }
        
        guard let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }) else {
            return
        }
        
        if userInitiated {
            if let update = ThreadRefreshLogic.readStateAfterUserRefresh(postNosAfter: postNos) {
                watched.lastReadPostNo = update.lastReadPostNo
                watched.lastSeenPostNo = update.lastSeenPostNo
                watched.newReplyCount = update.newReplyCount
                watched.lastChecked = Date()
            }
        } else {
            if let update = ThreadRefreshLogic.autoRefreshUpdate(
                currentMarkerPostNo: newRepliesMarkerPostNo,
                lastReadPostNo: watched.lastReadPostNo,
                lastSeenPostNo: watched.lastSeenPostNo,
                postNosAfter: postNos
            ) {
                newRepliesMarkerPostNo = update.markerPostNo
                watched.lastSeenPostNo = update.lastSeenPostNo
                watched.newReplyCount = update.newReplyCount
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
    var myPostNumbers: [Int] = []
    var posterPostCounts: [String: Int] = [:]
    var onImageTap: ((URL) -> Void)?
    var onPostNumberTap: ((Int) -> Void)?
    var onPosterIDTap: ((String) -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var showPosterPostCount = false

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
                        .onTapGesture {
                            onPosterIDTap?(id)
                        }
                        .onLongPressGesture(
                            minimumDuration: 0.3,
                            pressing: { pressing in
                                showPosterPostCount = pressing
                            },
                            perform: {}
                        )
                        .overlay(alignment: .top) {
                            if showPosterPostCount, let count = posterPostCounts[id] {
                                Text("\(count) post\(count == 1 ? "" : "s") by this ID")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                                    .fixedSize()
                                    .offset(y: -60)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                    .animation(.easeOut(duration: 0.15), value: showPosterPostCount)
                                    .zIndex(100)
                            }
                        }
                }
                // Country flag (emoji)
                if let emoji = post.countryEmoji {
                    Text(emoji)
                        .font(.caption)
                        .help(post.countryName ?? "")
                }
                // Board-specific meme flag (image)
                if let flagURL = post.boardFlagURL {
                    AnimatedImageView(url: flagURL)
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

            // Media (Image or Video) — tap to expand
            if let url = post.imageURL {
                VStack(alignment: .leading, spacing: 4) {
                    if post.ext == ".webm" || post.ext == ".mp4" {
                        // Video thumbnail with play indicator
                        ZStack {
                            if let thumbURL = post.thumbnailURL {
                                AsyncImage(url: thumbURL) { img in
                                    img.resizable().scaledToFit()
                                } placeholder: {
                                    Color.secondary.opacity(0.2)
                                        .frame(height: 120)
                                }
                            }
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                        .frame(maxWidth: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { onImageTap?(url) }
                    } else if post.ext == ".gif" {
                        // Animated GIF
                        AnimatedImageView(url: url)
                            .frame(maxWidth: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { onImageTap?(url) }
                    } else {
                        // Static Image
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
                    
                    // Filename display
                    if let filename = post.filename, let ext = post.ext {
                        Text("\(filename)\(ext)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            // Comment — rendered with full HTML (greentext, quote links, entities, etc.)
            if let html = post.com, !html.isEmpty {
                Text(PostHTMLRenderer.render(html, myPostNumbers: myPostNumbers))
                    .font(.body)
            }

            Text(post.now)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Reply count pills
            if !replyingPosts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(replyingPosts, id: \.self) { replyNo in
                        let isYou = myPostNumbers.contains(replyNo)
                        Button {
                            if let url = URL(string: "chanology://post/\(replyNo)") {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(verbatim: ">>\(replyNo)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                if isYou {
                                    Text("(You)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.orange)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (isYou ? Color.orange : Color.accentColor).opacity(0.12),
                                in: Capsule()
                            )
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
    
    private var mediaType: MediaType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "webm":
            return .webm
        case "mp4":
            return .mp4
        case "gif":
            return .gif
        default:
            return .image
        }
    }
    
    enum MediaType {
        case webm, mp4, gif, image
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            switch mediaType {
            case .webm:
                WebMPlayerView(url: url)
            case .mp4:
                VideoPlayerView(url: url)
            case .gif:
                gifView
            case .image:
                imageView
            }

            closeButton
                .padding()
        }
        .onTapGesture { 
            if mediaType == .image {
                dismiss()
            }
        }
    }
    
    private var gifView: some View {
        AnimatedImageView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Video Player View

struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?
    
    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func setupPlayer() {
        // Create player with proper audio session configuration
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        // Set up looping
        looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        
        player = queuePlayer
        player?.play()
    }
    
    private func cleanup() {
        player?.pause()
        looper = nil
        player = nil
    }
}

// MARK: - WebM Player View

struct WebMPlayerView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Create HTML to play the video with looping
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                }
                body {
                    background-color: black;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    overflow: hidden;
                }
                video {
                    max-width: 100%;
                    max-height: 100vh;
                    width: auto;
                    height: auto;
                }
            </style>
        </head>
        <body>
            <video autoplay loop playsinline muted controls>
                <source src="\(url.absoluteString)" type="video/webm">
                Your browser does not support the video tag.
            </video>
            <script>
                // Try to play with sound if possible
                const video = document.querySelector('video');
                video.muted = false;
                video.play().catch(() => {
                    // If autoplay with sound fails, try muted
                    video.muted = true;
                    video.play();
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Animated Image View (for GIFs)

struct AnimatedImageView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Load the image asynchronously
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                // Create animated image from GIF data
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let count = CGImageSourceGetCount(source)
                    
                    if count > 1 {
                        // Animated GIF
                        var images: [UIImage] = []
                        var totalDuration: TimeInterval = 0
                        
                        for i in 0..<count {
                            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                                // Get frame duration
                                var duration: TimeInterval = 0.1 // Default
                                if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                                   let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                                    if let delayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, delayTime > 0 {
                                        duration = delayTime
                                    } else if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval {
                                        duration = delayTime
                                    }
                                }
                                
                                totalDuration += duration
                                images.append(UIImage(cgImage: cgImage))
                            }
                        }
                        
                        await MainActor.run {
                            imageView.animationImages = images
                            imageView.animationDuration = totalDuration
                            imageView.animationRepeatCount = 0 // Infinite loop
                            imageView.startAnimating()
                        }
                    } else if count == 1, let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        // Static image
                        await MainActor.run {
                            imageView.image = UIImage(cgImage: cgImage)
                        }
                    }
                }
            } catch {
                // Silently fail or show placeholder
                print("Failed to load animated image: \(error)")
            }
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // No updates needed
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
    flagName: String? = nil,
    closed: Int? = nil,
    archived: Int? = nil
) -> Post {
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": no, "now": "01/01/25(Wed)12:30:00",
        "name": "Anonymous", "id": id as Any,
        "com": com, "resto": resto, "sub": sub as Any,
        "country": country as Any, "country_name": countryName as Any,
        "board_flag": boardFlag as Any, "flag_name": flagName as Any,
        "closed": closed as Any, "archived": archived as Any
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
            subject: "Post your desktop / tech setups. And here ill add some obnoxiously long text for the title.",
            mockPosts: [
                mockPost(no: 12345, com: "Post your desktops and rate others. I&#039;ll start.", resto: 0, sub: "Some subject"),
                mockPost(no: 12346, com: ##"<span class="quote">&gt;be me</span><br>&gt;write Swift code all day<br><a href="#p12345" class="quotelink">&gt;&gt;12345</a><br>genuinely enjoying it &#039;desu"##, resto: 12345),
                mockPost(no: 12347, com: "Anyone else think Rust is overrated? I&#039;ve been writing C for 20 years and never had memory issues.", id: nil, resto: 12345),
            ]
        )
    }
    .modelContainer(for: WatchedThread.self, inMemory: true)
}

#Preview("Thread — Archived") {
    NavigationStack {
        ThreadView(
            board: "g",
            threadNo: 12345,
            subject: "Post your desktop / tech setups.",
            mockPosts: [
                mockPost(no: 12345, com: "Post your desktops and rate others. I&#039;ll start.", resto: 0, sub: "Post your desktop / tech setups.", closed: 1, archived: 1),
                mockPost(no: 12346, com: "Nice setup anon", resto: 12345),
                mockPost(no: 12347, com: "Thread archived, RIP", resto: 12345),
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

#Preview("Post — with webm") {
    var post = mockPost(
        no: 11111,
        com: "Check out this sick webm",
        resto: 99999
    )
    // Simulate a webm attachment
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": 11111,
        "now": "01/01/25(Wed)12:30:00",
        "name": "Anonymous",
        "com": "Check out this sick webm",
        "resto": 99999,
        "tim": 1234567890,
        "ext": ".webm",
        "filename": "cool_video",
        "w": 1920,
        "h": 1080
    ] as [String: Any])
    var p = try! JSONDecoder().decode(Post.self, from: data)
    p._board = "g"
    return PostView(post: p)
        .padding()
}

#Preview("Post — with gif") {
    // Simulate a gif attachment
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": 11112,
        "now": "01/01/25(Wed)12:31:00",
        "name": "Anonymous",
        "com": "kek, have a gif",
        "resto": 99999,
        "tim": 1234567891,
        "ext": ".gif",
        "filename": "pepe_dance",
        "w": 500,
        "h": 500
    ] as [String: Any])
    var p = try! JSONDecoder().decode(Post.self, from: data)
    p._board = "g"
    return PostView(post: p)
        .padding()
}

#Preview("Post — with mp4") {
    // Simulate an mp4 attachment
    let data = try! JSONSerialization.data(withJSONObject: [
        "no": 11113,
        "now": "01/01/25(Wed)12:32:00",
        "name": "Anonymous",
        "com": "posting from my iPhone",
        "resto": 99999,
        "tim": 1234567892,
        "ext": ".mp4",
        "filename": "IMG_1234",
        "w": 1920,
        "h": 1080
    ] as [String: Any])
    var p = try! JSONDecoder().decode(Post.self, from: data)
    p._board = "g"
    return PostView(post: p)
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
