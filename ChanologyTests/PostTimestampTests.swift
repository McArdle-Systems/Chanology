import Foundation
import Testing
@testable import Chanology

private func zone(_ identifier: String) -> TimeZone {
    TimeZone(identifier: identifier)!
}

@Test func timestamp_easternDaylight_matchesAPINowString() {
    // Real catalog entry: "now" was "04/25/25(Fri)16:24:10", "time" was 1745612650.
    let result = PostTimestamp.string(time: 1745612650, fallback: "", timeZone: zone("America/New_York"))
    #expect(result == "04/25/25(Fri)16:24:10")
}

@Test func timestamp_convertsToCentralDuringDaylightSaving() {
    let result = PostTimestamp.string(time: 1745612650, fallback: "", timeZone: zone("America/Chicago"))
    #expect(result == "04/25/25(Fri)15:24:10")
}

@Test func timestamp_convertsToCentralDuringStandardTime() {
    // 2026-01-01T00:00:00Z
    let result = PostTimestamp.string(time: 1767225600, fallback: "", timeZone: zone("America/Chicago"))
    #expect(result == "12/31/25(Wed)18:00:00")
}

@Test func timestamp_missingTime_usesFallback() {
    let result = PostTimestamp.string(time: nil, fallback: "01/01/25(Wed)12:00:00")
    #expect(result == "01/01/25(Wed)12:00:00")
}

@Test func post_decodesTimeAndFormatsIt() throws {
    let data = Data(#"{"no":1,"now":"ignored","resto":0,"time":1745612650}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.time == 1745612650)
}

@Test func catalogThread_decodesWithoutTime() throws {
    let data = Data(#"{"no":1,"now":"fallback","replies":0,"images":0,"last_modified":1}"#.utf8)
    let thread = try JSONDecoder().decode(CatalogThread.self, from: data)
    #expect(thread.time == nil)
    #expect(thread.displayTimestamp == "fallback")
}

// MARK: - Media slot

@Test func mediaSlot_usesFullImageRatioAtFixedWidth() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"w":1000,"h":500,"tn_w":125,"tn_h":62}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.mediaSlotSize == CGSize(width: 260, height: 130))
}

@Test func mediaSlot_withoutDimensions_usesFixedFallback() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.mediaSlotSize == CGSize(width: 260, height: 120))
}
