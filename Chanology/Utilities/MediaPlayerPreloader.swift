import AVFoundation
import WebKit

/// Pre-warms heavyweight media infrastructure so the first video playback is fast.
///
/// The main costs on first playback are:
/// - WKWebView: Spinning up WebKit's browser engine process (~1-2s on first init)
/// - AVAudioSession: First-time audio category configuration
///
/// After the first WKWebView is created, subsequent ones reuse the already-running
/// WebKit process and are near-instant. This class creates a throwaway WKWebView
/// early so the real one used for WebM playback doesn't pay the startup cost.
@MainActor
final class MediaPlayerPreloader {
    static let shared = MediaPlayerPreloader()

    private var hasWarmedWebKit = false
    private var hasWarmedAudio = false
    /// Kept alive so the WebKit process stays warm.
    private var warmWebView: WKWebView?

    private init() {}

    /// Call once (e.g. when a thread view appears) to pre-warm media systems.
    /// Work is dispatched asynchronously so it never blocks the caller.
    func warmUp() {
        if !hasWarmedWebKit {
            hasWarmedWebKit = true
            // WKWebView must be created on the main thread, but we wrap it
            // in a Task so it yields and doesn't block the current await chain.
            Task { @MainActor in
                let config = WKWebViewConfiguration()
                config.allowsInlineMediaPlayback = true
                config.mediaTypesRequiringUserActionForPlayback = []
                warmWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            }
        }

        if !hasWarmedAudio {
            hasWarmedAudio = true
            Task.detached(priority: .utility) {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }
}
