import Testing
import Photos
@testable import Chanology

// MARK: - Classification

@Test func mediaKind_classifiesByExtension_ignoringDotAndCase() {
    #expect(SavableMediaKind(pathExtension: "jpg") == .image(ext: "jpg"))
    #expect(SavableMediaKind(pathExtension: ".PNG") == .image(ext: "png"))
    #expect(SavableMediaKind(pathExtension: "gif") == .gif)
    #expect(SavableMediaKind(pathExtension: ".webm") == .webm)
    #expect(SavableMediaKind(pathExtension: "mp4") == .mp4)
    #expect(SavableMediaKind(pathExtension: "pdf") == .other(ext: "pdf"))
}

// MARK: - Photos destination

@Test func mediaKind_imagesAndGifsSaveAsPhotos() {
    #expect(SavableMediaKind.image(ext: "jpg").photosResourceType == .photo)
    #expect(SavableMediaKind.gif.photosResourceType == .photo)
}

@Test func mediaKind_mp4SavesAsVideo() {
    #expect(SavableMediaKind.mp4.photosResourceType == .video)
}

@Test func mediaKind_webmAndOtherCannotGoToPhotos() {
    // Photos can't decode WebM; these fall back to Save to Files.
    #expect(SavableMediaKind.webm.canSaveToPhotos == false)
    #expect(SavableMediaKind.other(ext: "pdf").canSaveToPhotos == false)
}

// MARK: - Pasteboard types

@Test func mediaKind_pasteboardTypes() {
    #expect(SavableMediaKind.gif.pasteboardType == "com.compuserve.gif")
    #expect(SavableMediaKind.image(ext: "jpg").pasteboardType == "public.jpeg")
    #expect(SavableMediaKind.image(ext: "png").pasteboardType == "public.png")
    #expect(SavableMediaKind.mp4.pasteboardType == "public.mpeg-4")
    #expect(SavableMediaKind.webm.pasteboardType == "org.webmproject.webm")
}

// MARK: - Filenames

@Test func mediaKind_suggestedFilename_prefersOriginalName() {
    let name = SavableMediaKind.webm.suggestedFilename(originalName: "funny cat", fallbackName: "1731700000000")
    #expect(name == "funny cat.webm")
}

@Test func mediaKind_suggestedFilename_fallsBackToCDNName() {
    #expect(SavableMediaKind.gif.suggestedFilename(originalName: nil, fallbackName: "1731700000000") == "1731700000000.gif")
    #expect(SavableMediaKind.gif.suggestedFilename(originalName: "", fallbackName: "1731700000000") == "1731700000000.gif")
}

@Test func mediaKind_suggestedFilename_stripsPathSeparators() {
    let name = SavableMediaKind.image(ext: "png").suggestedFilename(originalName: "a/b:c", fallbackName: "x")
    #expect(name == "a_b_c.png")
}
