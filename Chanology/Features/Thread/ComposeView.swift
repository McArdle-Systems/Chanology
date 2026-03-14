import SwiftUI
import PhotosUI

/// Compose sheet for posting a reply to a thread.
struct ComposeView: View {
    let board: String
    let threadNo: Int
    let selectedQuotes: [Int]
    /// Called after a successful post with the new post number.
    var onPosted: ((Int) async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageFilename: String?
    @State private var imageThumbnail: UIImage?
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false

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
                imageFilename: imageFilename
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
