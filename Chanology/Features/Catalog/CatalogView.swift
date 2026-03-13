import SwiftUI

struct CatalogView: View {
    let board: Board
    @State private var vm: CatalogViewModel

    init(board: Board) {
        self.board = board
        _vm = State(initialValue: CatalogViewModel(board: board))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.threads.isEmpty {
                ProgressView("Loading /\(board.board)/…")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredThreads) { thread in
                            NavigationLink(value: thread) {
                                CatalogThreadRow(thread: thread, board: board.board)
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
        .searchable(text: $vm.searchText, prompt: "Search threads")
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
    }
}

struct CatalogThreadRow: View {
    let thread: CatalogThread
    let board: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            if let url = thread.thumbnailURL(board: board) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 80, height: 80)
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
        .contentShape(Rectangle())
    }
}

@Observable
@MainActor
class CatalogViewModel {
    let board: Board
    var threads: [CatalogThread] = []
    var searchText: String = ""
    var isLoading = false
    var error: Error?

    init(board: Board) {
        self.board = board
    }

    var filteredThreads: [CatalogThread] {
        guard !searchText.isEmpty else { return threads }
        return threads.filter { thread in
            thread.sub?.localizedCaseInsensitiveContains(searchText) == true ||
            thread.plainTextComment?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await ChanAPI.shared.catalog(board: board.board)
        } catch {
            self.error = error
        }
    }
}
