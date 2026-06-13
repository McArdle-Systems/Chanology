import Testing
@testable import Chanology

// MARK: - isNewThread

@Test func composeMode_reply_isNotNewThread() {
    #expect(ComposeMode.reply(threadNo: 12345).isNewThread == false)
}

@Test func composeMode_newThread_isNewThread() {
    #expect(ComposeMode.newThread.isNewThread == true)
}

// MARK: - threadNoForReply

@Test func composeMode_reply_returnsThreadNo() {
    #expect(ComposeMode.reply(threadNo: 12345).threadNoForReply == 12345)
}

@Test func composeMode_newThread_returnsZeroForReplyThreadNo() {
    // resto=0 is the on-wire signal that means "this is a new thread".
    #expect(ComposeMode.newThread.threadNoForReply == 0)
}

// MARK: - Equatable

@Test func composeMode_replyEquality_matchesByThreadNo() {
    #expect(ComposeMode.reply(threadNo: 1) == ComposeMode.reply(threadNo: 1))
    #expect(ComposeMode.reply(threadNo: 1) != ComposeMode.reply(threadNo: 2))
    #expect(ComposeMode.reply(threadNo: 1) != ComposeMode.newThread)
}
