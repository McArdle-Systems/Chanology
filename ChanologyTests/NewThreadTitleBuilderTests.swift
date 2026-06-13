import Testing
@testable import Chanology

// MARK: - Subject takes precedence

@Test func title_subjectWins_overComment() {
    let title = NewThreadTitleBuilder.title(
        subject: "What's your dev setup?",
        comment: "Some comment body",
        threadNo: 42
    )
    #expect(title == "What's your dev setup?")
}

@Test func title_subjectTrimmedWhitespace() {
    let title = NewThreadTitleBuilder.title(
        subject: "  Hello   ",
        comment: "ignored",
        threadNo: 1
    )
    #expect(title == "Hello")
}

// MARK: - Comment fallback

@Test func title_emptySubject_usesCommentFirstLine() {
    let title = NewThreadTitleBuilder.title(
        subject: "",
        comment: "first line\nsecond line",
        threadNo: 100
    )
    #expect(title == "first line")
}

@Test func title_whitespaceSubject_usesCommentFirstLine() {
    let title = NewThreadTitleBuilder.title(
        subject: "   \n  ",
        comment: "actual title",
        threadNo: 100
    )
    #expect(title == "actual title")
}

@Test func title_commentTrimmedBeforeSplitting() {
    let title = NewThreadTitleBuilder.title(
        subject: "",
        comment: "\n\n  hello world  \n",
        threadNo: 7
    )
    #expect(title == "hello world")
}

// MARK: - Truncation

@Test func title_longCommentLine_truncatedAt80WithEllipsis() {
    let longLine = String(repeating: "a", count: 100)
    let title = NewThreadTitleBuilder.title(
        subject: "",
        comment: longLine,
        threadNo: 1
    )
    #expect(title.count == NewThreadTitleBuilder.maxCommentTitleLength + 1) // 80 chars + ellipsis
    #expect(title.hasSuffix("…"))
    #expect(title.dropLast() == String(repeating: "a", count: NewThreadTitleBuilder.maxCommentTitleLength))
}

@Test func title_exactlyMaxLength_notTruncated() {
    let line = String(repeating: "x", count: NewThreadTitleBuilder.maxCommentTitleLength)
    let title = NewThreadTitleBuilder.title(
        subject: "",
        comment: line,
        threadNo: 1
    )
    #expect(title == line)
    #expect(!title.hasSuffix("…"))
}

@Test func title_truncationOnlyAppliesToCommentFallback_notSubject() {
    let longSubject = String(repeating: "S", count: 200)
    let title = NewThreadTitleBuilder.title(
        subject: longSubject,
        comment: "",
        threadNo: 1
    )
    // Subject is not truncated — the navigation bar handles long titles.
    #expect(title == longSubject)
}

// MARK: - Ultimate fallback

@Test func title_bothEmpty_usesThreadNumberFallback() {
    let title = NewThreadTitleBuilder.title(
        subject: "",
        comment: "",
        threadNo: 987654
    )
    #expect(title == "Thread #987654")
}

@Test func title_bothWhitespaceOnly_usesThreadNumberFallback() {
    let title = NewThreadTitleBuilder.title(
        subject: "   ",
        comment: "\n\n\t  ",
        threadNo: 12345
    )
    #expect(title == "Thread #12345")
}
