import WebKit

/// Pre-warms the WebKit browser engine process so the first WebM playback is fast.
///
/// Spinning up a WKWebView takes ~1-2s on first init. After the first instance is
/// created, subsequent ones reuse the already-running WebKit process and are
/// near-instant. This class creates a throwaway WKWebView early so the real one
/// used for WebM playback doesn't pay the startup cost.
///
/// Note: AVAudioSession is intentionally NOT pre-warmed here. Calling setActive(true)
/// eagerly interrupts any background audio the user has playing, even if they never
/// open a video. WebKit manages its own audio session when media actually plays.
@MainActor
final class MediaPlayerPreloader {
    static let shared = MediaPlayerPreloader()

    private var hasWarmedWebKit = false
    /// Kept alive so the WebKit process stays warm.
    private var warmWebView: WKWebView?

    private init() {}

    /// Call once (e.g. when a thread view appears) to pre-warm WebKit.
    /// Work is dispatched asynchronously so it never blocks the caller.
    func warmUp() {
        guard !hasWarmedWebKit else { return }
        hasWarmedWebKit = true
        Task { @MainActor in
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            warmWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        }
    }
}
