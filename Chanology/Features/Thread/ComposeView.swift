import SwiftUI
import PhotosUI

private struct MemeFlag: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    func flagURL(board: String) -> URL? {
        URL(string: "https://s.4cdn.org/image/flags/\(board)/\(code.lowercased()).gif")
    }
}



/// Compose sheet for posting a reply to a thread.
struct ComposeView: View {
    let board: String
    let threadNo: Int
    let selectedQuotes: [Int]
    /// Called after a successful post with the new post number.
    var onPosted: ((Int) async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var service = ForegroundRefreshService.shared
    @State private var commentText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageFilename: String?
    @State private var imageThumbnail: UIImage?
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var showFlagPicker = false
    @State private var selectedFlag: MemeFlag?

    private var availableFlags: [MemeFlag] {
        guard let flags = service.boards.first(where: { $0.board == board })?.boardFlags else {
            return []
        }
        return flags.map { MemeFlag(code: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comment editor
                TextEditor(text: $commentText)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Divider()

                // Attachment area
                HStack(spacing: 12) {
                    // Photo library picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                            .font(.callout)
                    }

                    // Files picker
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                            .font(.callout)
                    }

                    // Meme flag picker (boards that support it, e.g. /pol/)
                    if !availableFlags.isEmpty {
                        Button {
                            showFlagPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                if let selectedFlag, let url = selectedFlag.flagURL(board: board) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Color.clear
                                    }
                                    .frame(height: 12)
                                }
                                Text(selectedFlag?.name ?? "Flag")
                                    .font(.callout)
                                    .foregroundStyle(selectedFlag != nil ? .primary : .secondary)
                            }
                        }
                    }

                    Spacer()

                    // Thumbnail preview
                    if let imageThumbnail {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: imageThumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Button {
                                clearAttachment()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                            }
                            .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitPost() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Post")
                        }
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
            .disabled(isPosting)
            .onAppear { prefillQuotes() }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { await loadPhoto(from: newItem) }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url):
                    loadFile(from: url)
                case .failure:
                    break
                }
            }
            .sheet(isPresented: $showFlagPicker) {
                NavigationStack {
                    List {
                        Button {
                            selectedFlag = nil
                            showFlagPicker = false
                        } label: {
                            Text("None")
                                .foregroundStyle(selectedFlag == nil ? .primary : .secondary)
                        }
                        ForEach(availableFlags) { flag in
                            Button {
                                selectedFlag = flag
                                showFlagPicker = false
                            } label: {
                                HStack(spacing: 8) {
                                    if let url = flag.flagURL(board: board) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            ProgressView()
                                        }
                                        .frame(width: 20, height: 14)
                                    }
                                    Text(flag.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Flag")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showFlagPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Actions

    private func prefillQuotes() {
        guard !selectedQuotes.isEmpty else { return }
        commentText = selectedQuotes.map { ">>\($0)" }.joined(separator: "\n") + "\n"
    }

    private func submitPost() async {
        isPosting = true
        errorMessage = nil
        do {
            let postNo = try await ChanPostAPI.shared.submitPost(
                board: board,
                threadNo: threadNo,
                comment: commentText,
                imageData: imageData,
                imageFilename: imageFilename,
                flag: selectedFlag?.code
            )
            dismiss()
            await onPosted?(postNo)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPosting = false
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        imageData = data
        imageFilename = "image.jpg"
        if let uiImage = UIImage(data: data) {
            imageThumbnail = uiImage
        }
    }

    private func loadFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        imageData = data
        imageFilename = url.lastPathComponent
        if let uiImage = UIImage(data: data) {
            imageThumbnail = uiImage
        }
    }

    private func clearAttachment() {
        imageData = nil
        imageFilename = nil
        imageThumbnail = nil
        selectedPhotoItem = nil
    }
}
// MARK: - Previews

private let previewPolFlags: [String: String] = [
    "AC": "Anarcho-Capitalist", "AN": "Anarchist", "BL": "Black Nationalist",
    "CF": "Confederate", "CM": "Communist", "DM": "Democrat", "EU": "European",
    "FC": "Fascist", "GN": "Gadsden", "GY": "Gay", "JH": "Jihadi",
    "KN": "Kekistani", "MF": "Muslim", "NB": "National Bolshevik", "NT": "NATO",
    "NZ": "Nazi", "PC": "Hippie", "PR": "Pirate", "RE": "Republican",
    "TM": "Templar", "TR": "Tree Hugger", "UN": "United Nations", "WP": "White Supremacist",
]

#Preview("New Reply") {
    ComposeView(board: "g", threadNo: 12345678, selectedQuotes: [])
}

#Preview("With Quotes & Meme Flags") {
    ComposeView(board: "pol", threadNo: 12345678, selectedQuotes: [12345680, 12345692])
        .task {
            let service = ForegroundRefreshService.shared
            if !service.boards.contains(where: { $0.board == "pol" }) {
                service.boards.append(
                    Board(board: "pol", title: "Politically Incorrect", wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil, boardFlags: previewPolFlags)
                )
            }
        }
}

#Preview("With Meme Flags") {
    ComposeView(board: "pol", threadNo: 12345678, selectedQuotes: [])
        .task {
            let service = ForegroundRefreshService.shared
            if !service.boards.contains(where: { $0.board == "pol" }) {
                service.boards.append(
                    Board(board: "pol", title: "Politically Incorrect", wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 4194304, maxWebmFilesize: 3145728, maxCommentChars: 2000, isArchived: nil, boardFlags: previewPolFlags)
                )
            }
        }
}

