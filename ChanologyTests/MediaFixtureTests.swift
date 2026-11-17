import Testing
import UIKit
import AVFoundation
import ImageIO
@testable import Chanology

// Real (tiny) media files in ChanologyTests/Fixtures, generated with ffmpeg:
// 64x48, 1s, 10fps test pattern. Read straight from the source tree — the test
// target has no resources phase, and the simulator can see the host filesystem.

enum MediaFixture: String, CaseIterable {
    case jpg, gif, webm, mp4

    var url: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/sample.\(rawValue)")
    }

    var kind: SavableMediaKind { SavableMediaKind(pathExtension: url.pathExtension) }

    var data: Data { get throws { try Data(contentsOf: url) } }
}

// MARK: - Fixtures are real media

@Test(arguments: MediaFixture.allCases)
func fixture_existsAndIsSmall(_ fixture: MediaFixture) throws {
    let data = try fixture.data
    #expect(!data.isEmpty)
    #expect(data.count < 20_000, "keep fixtures tiny")
}

@Test func fixture_jpgDecodesAsImage() throws {
    let image = try #require(UIImage(data: MediaFixture.jpg.data))
    #expect(image.size == CGSize(width: 64, height: 48))
}

@Test func fixture_gifIsAnimated() throws {
    let source = try #require(CGImageSourceCreateWithData(MediaFixture.gif.data as CFData, nil))
    #expect(CGImageSourceGetCount(source) > 1)
}

@Test func fixture_mp4IsPlayableVideo() async throws {
    let asset = AVURLAsset(url: MediaFixture.mp4.url)
    #expect(try await asset.load(.isPlayable))
    #expect(try await !asset.loadTracks(withMediaType: .video).isEmpty)
}

@Test func fixture_webmHasEBMLHeader() throws {
    // AVFoundation can't open WebM, so check the Matroska/EBML magic bytes instead.
    #expect(try MediaFixture.webm.data.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]))
}

// MARK: - Download

@MainActor
@Test(arguments: MediaFixture.allCases)
func download_writesBytesUnderSuggestedFilename(_ fixture: MediaFixture) async throws {
    let filename = fixture.kind.suggestedFilename(originalName: "my file", fallbackName: "123")
    let saved = try await MediaActionRunner.download(fixture.url, filename: filename)
    defer { try? FileManager.default.removeItem(at: saved.deletingLastPathComponent()) }

    #expect(saved.lastPathComponent == "my file.\(fixture.rawValue)")
    #expect(try Data(contentsOf: saved) == fixture.data)
}

@MainActor
@Test func download_sameFilenameTwice_doesNotCollide() async throws {
    let a = try await MediaActionRunner.download(MediaFixture.gif.url, filename: "x.gif")
    let b = try await MediaActionRunner.download(MediaFixture.gif.url, filename: "x.gif")
    defer {
        try? FileManager.default.removeItem(at: a.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: b.deletingLastPathComponent())
    }
    #expect(a != b)
}

// MARK: - Copy

@MainActor
@Test(arguments: MediaFixture.allCases)
func copy_putsRawBytesOnPasteboardUnderKindType(_ fixture: MediaFixture) throws {
    let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name("chanology-test-\(UUID().uuidString)"), create: true))
    defer { UIPasteboard.remove(withName: pasteboard.name) }

    try MediaActionRunner.copy(fixture.url, kind: fixture.kind, to: pasteboard)

    #expect(pasteboard.numberOfItems == 1)
    #expect(pasteboard.data(forPasteboardType: fixture.kind.pasteboardType) == (try fixture.data))
}

@MainActor
@Test func copy_gifKeepsAllFrames() throws {
    let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name("chanology-test-\(UUID().uuidString)"), create: true))
    defer { UIPasteboard.remove(withName: pasteboard.name) }

    try MediaActionRunner.copy(MediaFixture.gif.url, kind: .gif, to: pasteboard)

    let pasted = try #require(pasteboard.data(forPasteboardType: SavableMediaKind.gif.pasteboardType))
    let source = try #require(CGImageSourceCreateWithData(pasted as CFData, nil))
    #expect(CGImageSourceGetCount(source) > 1)
}

// MARK: - WebM playback

/// Loads the WebM fixture through the real WebMPlayerView page and waits for WebKit
/// to decode a frame. Catches both unplayable encodes (e.g. VP9 profile 1 / 4:4:4)
/// and WebKit refusing to read the local file.
@MainActor
@Test func webmFixture_decodesInWebMPlayerView() async throws {
    let webView = WebMPlayerView.makeWebView()
    webView.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
    let window = UIWindow(frame: webView.frame)
    window.addSubview(webView)
    window.isHidden = false
    defer { window.isHidden = true }

    WebMPlayerView.load(MediaFixture.webm.url, into: webView)

    var state: (readyState: Int, width: Int, error: Int) = (0, 0, 0)
    // Generous: the first WKWebView in a process spins up WebKit, which can take seconds.
    for _ in 0..<150 {
        try await Task.sleep(for: .milliseconds(100))
        let js = "(() => { const v = document.querySelector('video'); return v ? [v.readyState, v.videoWidth, v.error ? v.error.code : 0] : [0, 0, 0] })()"
        if let result = try? await webView.evaluateJavaScript(js) as? [Int], result.count == 3 {
            state = (result[0], result[1], result[2])
            if state.error != 0 || (state.readyState >= 2 && state.width > 0) { break }
        }
    }
    #expect(state.error == 0, "MediaError code \(state.error)")
    #expect(state.readyState >= 2, "video never got a frame (readyState \(state.readyState))")
    #expect(state.width == 64)
}
