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

    @State private var service = ForegroundRefreshService.shared
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
    @State private var quotedSnippet: String? = nil
    @State private var isAuthenticating = false
    @State private var showArchivedToast = false
    @State private var visiblePosts: Set<Int> = []
    @State private var lastKnownPostCount: Int = 0
    @Query private var watchedThreads: [WatchedThread]
    @Query private var allMyPosts: [MyPosts]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("threadToolbarSide") private var toolbarSide: FloatingToolbarSide = .trailing

    @State private var searchIsOpen = false
    @State private var searchText = ""
    @State private var searchMatches: [Int] = []
    @State private var currentMatchIndex = 0

    /// For mock/preview support only
    @State private var mockPosts: [Post]?

    init(board: String, threadNo: Int, subject: String, scrollToLastRead: Bool = false) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        self.scrollToLastRead = scrollToLastRead
    }

    fileprivate init(board: String, threadNo: Int, subject: String, mockPosts: [Post]) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        self.scrollToLastRead = false
        _mockPosts = State(initialValue: mockPosts)
    }

    /// Posts from the service (or mock data for previews)
    private var posts: [Post] {
        mockPosts ?? service.posts(board: board, threadNo: threadNo)
    }

    private var isLoading: Bool {
        mockPosts == nil && service.isThreadLoading(board: board, threadNo: threadNo)
    }

    private var threadError: Error? {
        mockPosts == nil ? service.getThreadError(board: board, threadNo: threadNo) : nil
    }

    private var isWatched: Bool {
        watchedThreads.contains { $0.board == board && $0.threadNo == threadNo }
    }

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView("Loading thread…")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(posts) { post in
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
                            .id("thread-bottom")
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

            // Fetch from the service (or use mock data for previews)
            if mockPosts == nil {
                await service.fetchThread(board: board, threadNo: threadNo)
            }

            replyMap = ReplyMapBuilder.build(from: posts)
            lastKnownPostCount = posts.count

            // Find the first post after the read boundary
            let marker = ThreadRefreshLogic.markerOnInitialLoad(
                lastReadPostNo: lastRead,
                postNos: posts.map(\.no)
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
        }
        .refreshable { await refreshThread(userInitiated: true) }
        .onDisappear {
            markVisiblePostsAsRead()
            // Evict cached posts if the thread isn't watched (save memory)
            if !isWatched {
                service.evictThread(board: board, threadNo: threadNo)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                markVisiblePostsAsRead()
            }
        }
        // React to posts changing from the background poller
        .onChange(of: posts.count) { oldCount, newCount in
            guard newCount > lastKnownPostCount, lastKnownPostCount > 0 else {
                lastKnownPostCount = newCount
                return
            }
            lastKnownPostCount = newCount
            onAutoRefreshPostsChanged()
        }
        .alert("Error", isPresented: .constant(threadError != nil)) {
            Button("OK") {
                if mockPosts == nil {
                    service.clearThreadError(board: board, threadNo: threadNo)
                }
            }
        } message: {
            Text(threadError?.localizedDescription ?? "")
        }
        .overlay {
            FloatingToolbar(actions: floatingToolbarActions, side: $toolbarSide)
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
        .overlay(alignment: .bottom) {
            if searchIsOpen {
                ThreadSearchBar(
                    text: $searchText,
                    matchCount: searchMatches.count,
                    currentIndex: searchMatches.isEmpty ? 0 : currentMatchIndex + 1,
                    onPrevious: { navigateMatch(forward: false) },
                    onNext: { navigateMatch(forward: true) },
                    onClose: { toggleSearch() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchIsOpen)
        .onChange(of: searchText) { _, _ in updateSearchMatches() }
        .sheet(isPresented: $showCompose, onDismiss: { quotedSnippet = nil }) {
            ComposeView(
                board: board,
                threadNo: threadNo,
                selectedQuotes: selectedQuotes,
                quotedSnippet: quotedSnippet,
                onPosted: { newPostNo in
                    selectedQuotes.removeAll()
                    // Track our post for (You) indicators
                    if let record = myPostsRecord {
                        record.addPost(newPostNo)
                    } else {
                        let record = MyPosts(board: board, threadNo: threadNo)
                        record.addPost(newPostNo)
                        modelContext.insert(record)
                    }
                    // Refresh thread to show new post
                    Task {
                        await service.fetchThread(board: board, threadNo: threadNo)
                        replyMap = ReplyMapBuilder.build(from: posts)
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
        guard let op = posts.first else { return false }
        return (op.closed ?? 0) != 0 || (op.archived ?? 0) != 0
    }

    private func triggerCompose() {
        if isThreadClosed {
            showArchivedToast = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showArchivedToast = false
            }
        } else if ChanPostAPI.shared.isAuthenticated {
            quotedSnippet = nil
            showCompose = true
        } else {
            Task {
                isAuthenticating = true
                do {
                    try await ChanPostAPI.shared.reauthenticateIfNeeded()
                    quotedSnippet = nil
                    showCompose = true
                } catch {
                    showLogin = true
                }
                isAuthenticating = false
            }
        }
    }

    private func scrollToTop() {
        guard let firstNo = posts.first?.no else { return }
        scrollToTarget(AnyHashable(firstNo), anchor: .top)
    }

    private func scrollToBottom() {
        scrollToTarget(AnyHashable("thread-bottom"), anchor: .bottom)
    }

    /// Two-pass scroll: an initial animated jump, then a re-scroll once the
    /// LazyVStack has finished laying out previously-offscreen rows. The
    /// follow-up corrects the "ends short" symptom caused by lazy
    /// row-height estimation.
    private func scrollToTarget(_ id: AnyHashable, anchor: UnitPoint) {
        guard let proxy = scrollProxy else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            proxy.scrollTo(id, anchor: anchor)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: anchor)
                }
            }
        }
    }

    private func toggleSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            searchIsOpen.toggle()
        }
        if !searchIsOpen {
            searchText = ""
            searchMatches = []
            currentMatchIndex = 0
            highlightedPostNo = nil
        }
    }

    private func updateSearchMatches() {
        guard !searchText.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            highlightedPostNo = nil
            return
        }
        let query = searchText.lowercased()
        let newMatches = posts.compactMap { post -> Int? in
            let inComment = post.plainTextComment?.lowercased().contains(query) == true
            let inSubject = post.decodedSubject?.lowercased().contains(query) == true
            return (inComment || inSubject) ? post.no : nil
        }
        searchMatches = newMatches
        currentMatchIndex = 0
        if !newMatches.isEmpty {
            scrollToMatch()
        } else {
            highlightedPostNo = nil
        }
    }

    private func navigateMatch(forward: Bool) {
        guard !searchMatches.isEmpty else { return }
        if forward {
            currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        } else {
            currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        }
        scrollToMatch()
    }

    private func scrollToMatch() {
        guard currentMatchIndex < searchMatches.count else { return }
        let postNo = searchMatches[currentMatchIndex]
        highlightedPostNo = nil
        scrollToTarget(AnyHashable(postNo), anchor: .center)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.2)) {
                highlightedPostNo = postNo
            }
        }
    }

    private var floatingToolbarActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "scroll-top",
                icon: "arrow.up",
                label: "Scroll to top",
                action: { scrollToTop() }
            ),
            ToolbarAction(
                id: "search",
                icon: "magnifyingglass",
                label: searchIsOpen ? "Close search" : "Search thread",
                role: searchIsOpen ? .prominent : .standard,
                action: { toggleSearch() }
            ),
            ToolbarAction(
                id: "watch",
                icon: isWatched ? "bell.fill" : "bell",
                label: isWatched ? "Stop watching" : "Watch thread",
                action: { toggleWatch() }
            ),
            ToolbarAction(
                id: "reply",
                icon: isAuthenticating ? "ellipsis" : "square.and.pencil",
                label: isThreadClosed ? "Thread archived" : "Reply",
                role: .prominent,
                isEnabled: !isAuthenticating,
                badge: (selectedQuotes.isEmpty || isThreadClosed) ? nil : "\(selectedQuotes.count)",
                action: { triggerCompose() }
            ),
            ToolbarAction(
                id: "scroll-bottom",
                icon: "arrow.down",
                label: "Scroll to bottom",
                action: { scrollToBottom() }
            ),
        ]
    }

    /// The MyPosts record for the current thread (if any).
    private var myPostsRecord: MyPosts? {
        let key = MyPosts.key(board: board, threadNo: threadNo)
        return allMyPosts.first(where: { $0.threadKey == key })
    }

    /// Whether the given post quotes one of the user's own posts.
    private func isReplyToUser(_ post: Post) -> Bool {
        guard let record = myPostsRecord, !record.postNumbers.isEmpty else { return false }
        let quoted = ReplyMapBuilder.quotedPosts(in: post)
        return quoted.contains(where: record.postNumbers.contains)
    }

    /// The post numbers this user has made in the current thread.
    private var myPostNumbers: [Int] {
        myPostsRecord?.postNumbers ?? []
    }

    /// Count of posts per poster ID in this thread.
    private var posterPostCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for post in posts {
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
            searchQuery: searchIsOpen && !searchText.isEmpty ? searchText : nil,
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
            },
            onQuote: { selected in
                quotedSnippet = selected
                DispatchQueue.main.async {
                    showCompose = true
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
            allPostNos: posts.map(\.no),
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
        if let lastPost = posts.last {
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
                lastSeenPostNo: posts.last?.no ?? 0
            )
            modelContext.insert(watched)
        }
    }

    /// Handle user-initiated refresh (pull-to-refresh or bottom button)
    private func refreshThread(userInitiated: Bool) async {
        let lastPostNoBefore = posts.last?.no

        await service.fetchThread(board: board, threadNo: threadNo)
        replyMap = ReplyMapBuilder.build(from: posts)
        lastKnownPostCount = posts.count

        let postNos = posts.map(\.no)

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
        }
    }

    /// Called when the background poller updates posts for this thread
    private func onAutoRefreshPostsChanged() {
        replyMap = ReplyMapBuilder.build(from: posts)

        guard let watched = watchedThreads.first(where: { $0.board == board && $0.threadNo == threadNo }) else {
            return
        }

        let postNos = posts.map(\.no)

        if let update = ThreadRefreshLogic.autoRefreshUpdate(
            currentMarkerPostNo: newRepliesMarkerPostNo,
            lastReadPostNo: watched.lastReadPostNo,
            lastSeenPostNo: watched.lastSeenPostNo,
            postNosAfter: postNos
        ) {
            newRepliesMarkerPostNo = update.markerPostNo
            // Note: lastSeenPostNo and newReplyCount are updated by the poller service itself
        }
    }
}

// MARK: - ThreadSearchBar

private struct ThreadSearchBar: View {
    @Binding var text: String
    let matchCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search thread…", text: $text)
                .focused($isFocused)
                .font(.system(size: 16))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                if matchCount > 0 {
                    Text("\(currentIndex) of \(matchCount)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Text("No results")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(matchCount == 0)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(matchCount == 0)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 4)
        .onAppear { isFocused = true }
    }
}

struct PostView: View {
    let post: Post
    var replyingPosts: [Int] = []
    var isQuoteSelected: Bool = false
    var myPostNumbers: [Int] = []
    var posterPostCounts: [String: Int] = [:]
    var searchQuery: String? = nil
    var onImageTap: ((URL) -> Void)?
    var onPostNumberTap: ((Int) -> Void)?
    var onPosterIDTap: ((String) -> Void)?
    var onQuote: ((String) -> Void)?

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
                if myPostNumbers.contains(post.no) {
                    Text("(You)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
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
                SelectablePostText(html: html, myPostNumbers: myPostNumbers, searchQuery: searchQuery) { selected in
                    onQuote?(selected)
                } onLinkTap: { url in
                    openURL(url)
                }
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
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color.accentColor)
                                if isYou {
                                    Text("(You)")
                                        .font(.caption2.monospaced())
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
                ZoomableImageView(url: url, onDismiss: { dismiss() })
                    .ignoresSafeArea()
            }

            closeButton
                .padding()
        }
        .onTapGesture {
            if mediaType != .image {
                dismiss()
            }
        }
    }

    private var gifView: some View {
        AnimatedImageView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

// MARK: - Zoomable Image View (UIScrollView-based)

struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    var onDismiss: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                imageView.image = image
                context.coordinator.updateLayout()
            }
        }.resume()

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var onDismiss: (() -> Void)?

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageView()
        }

        func centerImageView() {
            guard let imageView, let scrollView else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
        }

        func updateLayout() {
            guard let imageView, let scrollView, let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            let imageSize = image.size
            let fitScale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
            let scaledWidth = imageSize.width * fitScale
            let scaledHeight = imageSize.height * fitScale
            imageView.frame = CGRect(
                x: (boundsSize.width - scaledWidth) / 2,
                y: (boundsSize.height - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            scrollView.contentSize = CGSize(width: scaledWidth, height: scaledHeight)
            scrollView.minimumZoomScale = 1.0
            scrollView.zoomScale = 1.0
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2,
                    height: scrollView.bounds.height / 2
                )
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        @objc func handleSingleTap() {
            guard let scrollView else { return }
            if scrollView.zoomScale <= scrollView.minimumZoomScale {
                onDismiss?()
            }
        }
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
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)

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

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let count = CGImageSourceGetCount(source)

                    if count > 1 {
                        var images: [UIImage] = []
                        var totalDuration: TimeInterval = 0

                        for i in 0..<count {
                            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                                var duration: TimeInterval = 0.1
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
                            imageView.animationRepeatCount = 0
                            imageView.startAnimating()
                        }
                    } else if count == 1, let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        await MainActor.run {
                            imageView.image = UIImage(cgImage: cgImage)
                        }
                    }
                }
            } catch {
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
    country: String? = nil,
    countryName: String? = nil,
    boardFlag: String? = nil,
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

#Preview("Post — (You)") {
    let post = mockPost(no: 11111, com: "Just posted this myself.", resto: 99999)
    return PostView(post: post, myPostNumbers: [11111])
        .padding()
}

#Preview("Post — bare URLs (real API format)") {
    VStack(spacing: 0) {
        // Real API examples from /g/ — bare URLs with <wbr> mid-URL, no anchor tags
        PostView(post: mockPost(
            no: 11114,
            com: "check this out https://youtube.com/watch?v=wOv6z9L<wbr>kHGs lmao",
            resto: 99999
        ))
        Divider().padding(.leading, 16)
        PostView(post: mockPost(
            no: 11115,
            com: ##"<a href="#p11114" class="quotelink">&gt;&gt;11114</a><br>try watching https://www.youtube.com/watch?v=oV9<wbr>rvDllKEg"##,
            resto: 99999
        ))
        Divider().padding(.leading, 16)
        PostView(post: mockPost(
            no: 11116,
            com: "bare url no wbr: https://news.ycombinator.com/item?id=12345 trust me",
            resto: 99999
        ))
    }
}
