import SwiftUI
import SwiftData

struct ThreadView: View {
    let board: String
    let threadNo: Int
    let subject: String

    @State private var vm: ThreadViewModel
    @State private var showSubjectPopover = false
    @Query private var watchedThreads: [WatchedThread]
    @Environment(\.modelContext) private var modelContext

    init(board: String, threadNo: Int, subject: String) {
        self.board = board
        self.threadNo = threadNo
        self.subject = subject
        _vm = State(initialValue: ThreadViewModel(board: board, threadNo: threadNo))
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showSubjectPopover = true
                } label: {
                    Text(subject)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 200)
                }
                .popover(isPresented: $showSubjectPopover) {
                    Text(subject)
                        .font(.body)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await ChanAPI.shared.thread(board: board, no: threadNo)
        } catch {
            self.error = error
        }
    }
}
