import Testing
import Foundation
@testable import Chanology

// MARK: - Post decoding

private let minimalPostJSON = """
{"no":12345,"now":"03/15/26(Sun)10:00:00","resto":0}
"""

private let fullPostJSON = """
{
    "no": 99999,
    "now": "03/15/26(Sun)12:30:00",
    "name": "Anonymous",
    "trip": "!abc123",
    "id": "xYz789",
    "capcode": "mod",
    "com": "<b>Hello</b>",
    "sub": "Test Subject &amp; More",
    "tim": 1700000000000,
    "filename": "image",
    "ext": ".png",
    "fsize": 102400,
    "w": 1920,
    "h": 1080,
    "tn_w": 250,
    "tn_h": 140,
    "md5": "abc123==",
    "resto": 12345,
    "replies": 50,
    "images": 10,
    "sticky": 0,
    "closed": 0,
    "archived": 0,
    "bumplimit": 0,
    "imagelimit": 0,
    "country": "US",
    "country_name": "United States",
    "board_flag": "AC",
    "flag_name": "Anarcho-Capitalist"
}
"""

@Test func post_decodesMinimalJSON() throws {
    let data = Data(minimalPostJSON.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.no == 12345)
    #expect(post.resto == 0)
    #expect(post.isOP == true)
    #expect(post.com == nil)
    #expect(post.name == nil)
}

@Test func post_decodesFullJSON() throws {
    let data = Data(fullPostJSON.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.no == 99999)
    #expect(post.name == "Anonymous")
    #expect(post.trip == "!abc123")
    #expect(post.posterID == "xYz789")
    #expect(post.capcode == "mod")
    #expect(post.com == "<b>Hello</b>")
    #expect(post.sub == "Test Subject &amp; More")
    #expect(post.tim == 1700000000000)
    #expect(post.filename == "image")
    #expect(post.ext == ".png")
    #expect(post.fsize == 102400)
    #expect(post.w == 1920)
    #expect(post.h == 1080)
    #expect(post.tnW == 250)
    #expect(post.tnH == 140)
    #expect(post.resto == 12345)
    #expect(post.isOP == false)
    #expect(post.country == "US")
    #expect(post.countryName == "United States")
    #expect(post.boardFlag == "AC")
    #expect(post.flagName == "Anarcho-Capitalist")
}

@Test func post_isOP_trueWhenRestoIsZero() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.isOP == true)
}

@Test func post_isOP_falseWhenRestoIsNonZero() throws {
    let data = Data(#"{"no":2,"now":"","resto":1}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.isOP == false)
}

@Test func post_id_equalsNo() throws {
    let data = Data(#"{"no":42,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.id == 42)
    #expect(post.id == post.no)
}

// MARK: - Post computed URLs

@Test func post_thumbnailURL_withBoardAndTim() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"tim":1700000000000}"#.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "g"
    #expect(post.thumbnailURL?.absoluteString == "https://i.4cdn.org/g/1700000000000s.jpg")
}

@Test func post_thumbnailURL_nilWithoutBoard() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"tim":1700000000000}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.thumbnailURL == nil)
}

@Test func post_thumbnailURL_nilWithoutTim() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "g"
    #expect(post.thumbnailURL == nil)
}

@Test func post_imageURL_withBoardTimExt() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"tim":1700000000000,"ext":".png"}"#.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "g"
    #expect(post.imageURL?.absoluteString == "https://i.4cdn.org/g/1700000000000.png")
}

@Test func post_imageURL_nilWithoutExt() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"tim":1700000000000}"#.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "g"
    #expect(post.imageURL == nil)
}

// MARK: - Post country emoji

@Test func post_countryEmoji_US() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"country":"US"}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.countryEmoji == "🇺🇸")
}

@Test func post_countryEmoji_JP() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"country":"JP"}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.countryEmoji == "🇯🇵")
}

@Test func post_countryEmoji_nilWhenMissing() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.countryEmoji == nil)
}

@Test func post_countryEmoji_nilWhenInvalidLength() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"country":"USA"}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.countryEmoji == nil)
}

// MARK: - Post board flag URL

@Test func post_boardFlagURL_lowercasedPath() throws {
    let data = Data(##"{"no":1,"now":"","resto":0,"board_flag":"CM","flag_name":"Communist"}"##.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "pol"
    #expect(post.boardFlagURL?.absoluteString == "https://s.4cdn.org/image/flags/pol/cm.gif")
}

@Test func post_boardFlagURL_nilWithoutBoard() throws {
    let data = Data(##"{"no":1,"now":"","resto":0,"board_flag":"CM"}"##.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.boardFlagURL == nil)
}

@Test func post_boardFlagURL_nilWithoutFlag() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    var post = try JSONDecoder().decode(Post.self, from: data)
    post._board = "pol"
    #expect(post.boardFlagURL == nil)
}

// MARK: - Post decoded subject

@Test func post_decodedSubject_decodesEntities() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"sub":"Tom &amp; Jerry"}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.decodedSubject == "Tom & Jerry")
}

@Test func post_decodedSubject_nilWhenNoSubject() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.decodedSubject == nil)
}

// MARK: - Post plain text comment

@Test func post_plainTextComment_stripsHTML() throws {
    let data = Data(#"{"no":1,"now":"","resto":0,"com":"<b>Hello</b><br>World"}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.plainTextComment == "Hello\nWorld")
}

@Test func post_plainTextComment_nilWhenNoCom() throws {
    let data = Data(#"{"no":1,"now":"","resto":0}"#.utf8)
    let post = try JSONDecoder().decode(Post.self, from: data)
    #expect(post.plainTextComment == nil)
}

// MARK: - Board decoding

private let boardJSON = """
{
    "board": "g",
    "title": "Technology",
    "ws_board": 1,
    "per_page": 15,
    "pages": 10,
    "max_filesize": 4194304,
    "max_webm_filesize": 3145728,
    "max_comment_chars": 2000,
    "is_archived": 1
}
"""

@Test func board_decodesJSON() throws {
    let data = Data(boardJSON.utf8)
    let board = try JSONDecoder().decode(Board.self, from: data)
    #expect(board.board == "g")
    #expect(board.title == "Technology")
    #expect(board.wsBoard == 1)
    #expect(board.isWorkSafe == true)
    #expect(board.perPage == 15)
    #expect(board.pages == 10)
    #expect(board.id == "g")
}

@Test func board_isWorkSafe_falseWhenZero() throws {
    let data = Data(#"{"board":"b","title":"Random","ws_board":0,"per_page":15,"pages":10,"max_filesize":4194304,"max_webm_filesize":3145728,"max_comment_chars":2000}"#.utf8)
    let board = try JSONDecoder().decode(Board.self, from: data)
    #expect(board.isWorkSafe == false)
}

// MARK: - CatalogThread decoding

private let catalogThreadJSON = """
{
    "no": 12345,
    "now": "03/15/26(Sun)10:00:00",
    "sub": "General Thread &amp; Discussion",
    "com": "<b>Welcome</b><br>Post here",
    "tim": 1700000000000,
    "ext": ".jpg",
    "replies": 100,
    "images": 20,
    "last_modified": 1700000500
}
"""

@Test func catalogThread_decodesJSON() throws {
    let data = Data(catalogThreadJSON.utf8)
    let thread = try JSONDecoder().decode(CatalogThread.self, from: data)
    #expect(thread.no == 12345)
    #expect(thread.replies == 100)
    #expect(thread.images == 20)
    #expect(thread.lastModified == 1700000500)
    #expect(thread.id == 12345)
}

@Test func catalogThread_thumbnailURL() throws {
    let data = Data(catalogThreadJSON.utf8)
    let thread = try JSONDecoder().decode(CatalogThread.self, from: data)
    let url = thread.thumbnailURL(board: "g")
    #expect(url?.absoluteString == "https://i.4cdn.org/g/1700000000000s.jpg")
}

@Test func catalogThread_decodedSubject() throws {
    let data = Data(catalogThreadJSON.utf8)
    let thread = try JSONDecoder().decode(CatalogThread.self, from: data)
    #expect(thread.decodedSubject == "General Thread & Discussion")
}

@Test func catalogThread_plainTextComment() throws {
    let data = Data(catalogThreadJSON.utf8)
    let thread = try JSONDecoder().decode(CatalogThread.self, from: data)
    #expect(thread.plainTextComment == "Welcome\nPost here")
}

// MARK: - Starred boards store

@Test @MainActor func starredStore_toggle_starsUnstarredBoard() {
    let store = StarredBoardsStore.shared
    store.boardIDs = []
    store.toggle("g")
    #expect(store.isStarred("g") == true)
}

@Test @MainActor func starredStore_toggle_unstarsStarredBoard() {
    let store = StarredBoardsStore.shared
    store.boardIDs = ["g"]
    store.toggle("g")
    #expect(store.isStarred("g") == false)
}

@Test @MainActor func starredStore_isStarred_falseForUnstarredBoard() {
    let store = StarredBoardsStore.shared
    store.boardIDs = ["a"]
    #expect(store.isStarred("g") == false)
}

@Test @MainActor func starredStore_toggle_doesNotAffectOtherBoards() {
    let store = StarredBoardsStore.shared
    store.boardIDs = ["a", "g"]
    store.toggle("g")
    #expect(store.isStarred("a") == true)
    #expect(store.isStarred("g") == false)
}

// MARK: - Board filtering

@Test @MainActor func service_workSafeBoards_excludesNSFW() {
    let service = ForegroundRefreshService()
    service.boards = [
        Board(board: "g", title: "Technology", wsBoard: 1, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil),
        Board(board: "b", title: "Random",     wsBoard: 0, perPage: 15, pages: 10, maxFilesize: 0, maxWebmFilesize: 0, maxCommentChars: 0, isArchived: nil, boardFlags: nil),
    ]
    #expect(service.workSafeBoards.map(\.board) == ["g"])
    #expect(service.nsfwBoards.map(\.board) == ["b"])
}

@Test @MainActor func service_boards_emptyBeforeFetch() {
    let service = ForegroundRefreshService()
    #expect(service.workSafeBoards.isEmpty)
    #expect(service.nsfwBoards.isEmpty)
}

// MARK: - ThreadResponse decoding

@Test func threadResponse_decodesPosts() throws {
    let json = #"{"posts":[{"no":1,"now":"","resto":0},{"no":2,"now":"","resto":1}]}"#
    let data = Data(json.utf8)
    let response = try JSONDecoder().decode(ThreadResponse.self, from: data)
    #expect(response.posts.count == 2)
    #expect(response.posts[0].no == 1)
    #expect(response.posts[1].no == 2)
}
