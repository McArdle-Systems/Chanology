import SwiftUI
import Photos
import UniformTypeIdentifiers

// MARK: - Media Kind

/// What a 4chan attachment is, as far as saving and copying are concerned.
/// Pure value logic so it can be unit-tested without Photos or UIKit.
enum SavableMediaKind: Equatable {
    case image(ext: String)
    case gif
    case mp4
    case webm
    case other(ext: String)

    init(pathExtension: String) {
        let ext = pathExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp": self = .image(ext: ext)
        case "gif": self = .gif
        case "mp4", "m4v", "mov": self = .mp4
        case "webm": self = .webm
        default: self = .other(ext: ext)
        }
    }

    var fileExtension: String {
        switch self {
        case .image(let ext), .other(let ext): return ext
        case .gif: return "gif"
        case .mp4: return "mp4"
        case .webm: return "webm"
        }
    }

    /// The UTType identifier used when putting the raw bytes on the pasteboard.
    var pasteboardType: String {
        switch self {
        case .webm:
            // iOS has no system-declared WebM type; use the registered identifier
            // so apps that understand WebM can take it.
            return "org.webmproject.webm"
        case .gif:
            return UTType.gif.identifier
        case .mp4:
            return UTType.mpeg4Movie.identifier
        case .image, .other:
            return UTType(filenameExtension: fileExtension)?.identifier ?? UTType.data.identifier
        }
    }

    /// Photos only accepts formats it can decode. WebM (and PDFs etc.) go to Files instead.
    var photosResourceType: PHAssetResourceType? {
        switch self {
        case .image, .gif: return .photo
        case .mp4: return .video
        case .webm, .other: return nil
        }
    }

    var canSaveToPhotos: Bool { photosResourceType != nil }

    var isVideo: Bool {
        switch self {
        case .mp4, .webm: return true
        default: return false
        }
    }

    /// Name for the saved/shared file: the poster's original filename when known,
    /// otherwise the CDN name. Path separators are stripped so it's a single component.
    func suggestedFilename(originalName: String?, fallbackName: String) -> String {
        let base = (originalName?.isEmpty == false ? originalName! : fallbackName)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(base).\(fileExtension)"
    }
}

// MARK: - Media Action

enum MediaAction {
    case save, copy, share
}

// MARK: - Media Saver

enum MediaSaverError: LocalizedError {
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .photosAccessDenied:
            return "Allow Chanology to add photos in Settings to save media."
        }
    }
}

/// Downloads a post's full-size media and saves, copies, or shares it.
/// Shows its own progress/result toast via `MediaActionHUD`.
@MainActor
@Observable
final class MediaActionRunner {
    enum Status: Equatable {
        case working(String)
        case done(String)
        case failed(String)
    }

    private(set) var status: Status?
    private var clearTask: Task<Void, Never>?

    func perform(_ action: MediaAction, url: URL, originalFilename: String?) {
        let kind = SavableMediaKind(pathExtension: url.pathExtension)
        let filename = kind.suggestedFilename(
            originalName: originalFilename,
            fallbackName: url.deletingPathExtension().lastPathComponent
        )
        Task {
            show(.working(kind.isVideo ? "Downloading video…" : "Downloading…"), autoClear: false)
            do {
                let fileURL = try await Self.download(url, filename: filename)
                switch action {
                case .save:
                    if kind.canSaveToPhotos {
                        try await Self.saveToPhotos(fileURL, kind: kind, filename: filename)
                        show(.done("Saved to Photos"))
                    } else {
                        clear()
                        Self.present(UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true))
                    }
                case .copy:
                    try Self.copy(fileURL, kind: kind)
                    show(.done("Copied"))
                case .share:
                    clear()
                    let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    Self.present(activity)
                }
            } catch {
                show(.failed(error.localizedDescription))
            }
        }
    }

    private func show(_ status: Status, autoClear: Bool = true) {
        clearTask?.cancel()
        withAnimation { self.status = status }
        guard autoClear else { return }
        clearTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { self.status = nil }
        }
    }

    private func clear() {
        clearTask?.cancel()
        withAnimation { status = nil }
    }

    // MARK: Helpers

    /// Downloads into a per-file temp directory so the file carries a human-readable name
    /// into Files and the share sheet. Hits URLCache when the viewer already loaded it.
    static func download(_ url: URL, filename: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedMedia", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Puts the file's raw bytes on the pasteboard under the kind's type, so it pastes
    /// as media rather than a link.
    static func copy(_ fileURL: URL, kind: SavableMediaKind, to pasteboard: UIPasteboard = .general) throws {
        let data = try Data(contentsOf: fileURL)
        pasteboard.setItems([[kind.pasteboardType: data]])
    }

    /// `nonisolated` matters: Photos runs the change block on its own transaction queue.
    /// Declared inside this @MainActor type, the closure would inherit main-actor
    /// isolation and Swift 6's runtime check traps (EXC_BREAKPOINT) when Photos calls it.
    nonisolated static func saveToPhotos(_ fileURL: URL, kind: SavableMediaKind, filename: String) async throws {
        guard let resourceType = kind.photosResourceType else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MediaSaverError.photosAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            // Adding the file as a resource (rather than via UIImage) keeps GIF animation intact.
            PHAssetCreationRequest.forAsset().addResource(with: resourceType, fileURL: fileURL, options: options)
        }
    }

    private static func present(_ controller: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        // iPad requires an anchor for popovers.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

// MARK: - Menu Items

/// Save / Copy / Share buttons, for use inside a `Menu` or `.contextMenu`.
struct MediaActionMenuItems: View {
    let url: URL
    let originalFilename: String?
    let runner: MediaActionRunner

    var body: some View {
        let kind = SavableMediaKind(pathExtension: url.pathExtension)
        Button {
            runner.perform(.save, url: url, originalFilename: originalFilename)
        } label: {
            if kind.canSaveToPhotos {
                Label(kind.isVideo ? "Save Video" : "Save to Photos", systemImage: "square.and.arrow.down")
            } else {
                Label("Save to Files", systemImage: "folder")
            }
        }
        Button {
            runner.perform(.copy, url: url, originalFilename: originalFilename)
        } label: {
            Label(kind.isVideo ? "Copy Video" : "Copy Image", systemImage: "doc.on.doc")
        }
        Button {
            runner.perform(.share, url: url, originalFilename: originalFilename)
        } label: {
            Label("Share…", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - HUD

struct MediaActionHUD: ViewModifier {
    let runner: MediaActionRunner

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let status = runner.status {
                HStack(spacing: 8) {
                    switch status {
                    case .working(let text):
                        ProgressView().tint(.white)
                        Text(text)
                    case .done(let text):
                        Image(systemName: "checkmark.circle.fill")
                        Text(text)
                    case .failed(let text):
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(text)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.bottom, 40)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func mediaActionHUD(_ runner: MediaActionRunner) -> some View {
        modifier(MediaActionHUD(runner: runner))
    }
}
