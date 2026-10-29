import HerdrKit
import HerdrKitTesting
import HUDCore
import Testing
import Transcript
@testable import HUDApp

@Suite struct PanelDetailBodyTests {
    typealias DetailBody = PanelController.DetailBody
    typealias TranscriptFeed = PanelController.TranscriptFeed
    private let session = AgentSessionRef(kind: .path, value: "/tmp/session.jsonl")

    // MARK: Body rule

    @Test(arguments: [TranscriptFeed.State.waiting, .available, .ended])
    func blockedAgentShowsTheBlockedCardEvenWithATranscript(transcript: TranscriptFeed.State) {
        let agent = AgentSnapshot.fake(pane: "w1:p1", status: .blocked, session: session)
        #expect(DetailBody(agent, transcript: transcript) == .blocked)
    }

    @Test(arguments: [AgentStatus.idle, .working, .done, .unknown])
    func agentWithAReadableTranscriptShowsChat(status: AgentStatus) {
        let agent = AgentSnapshot.fake(pane: "w1:p1", status: status, session: session)
        #expect(DetailBody(agent, transcript: .available) == .chat(session))
    }

    @Test(arguments: [AgentStatus.idle, .working, .done, .unknown])
    func agentWithoutASessionShowsScreenText(status: AgentStatus) {
        #expect(DetailBody(.fake(pane: "w1:p1", status: status), transcript: .waiting) == .screenText)
    }

    @Test(arguments: [AgentStatus.idle, .working, .done, .unknown], [TranscriptFeed.State.waiting, .ended])
    func agentWhoseTranscriptIsNotAvailableShowsScreenText(status: AgentStatus, transcript: TranscriptFeed.State) {
        let agent = AgentSnapshot.fake(pane: "w1:p1", status: status, session: session)
        #expect(DetailBody(agent, transcript: transcript) == .screenText)
    }

    @Test(arguments: [AgentStatus.blocked, .working, .done])
    func desktopSessionWithAReadableTranscriptShowsChatEvenWhenBlocked(status: AgentStatus) {
        #expect(DetailBody(.desktop("s1", status: status, transcript: session), transcript: .available) == .chat(session))
    }

    @Test(arguments: [TranscriptFeed.State.waiting, .ended])
    func desktopSessionWithoutAReadableTranscriptShowsNoScreenText(transcript: TranscriptFeed.State) {
        #expect(DetailBody(.desktop("s1", transcript: session), transcript: transcript) == .noTranscript)
        #expect(DetailBody(.desktop("s1", status: .blocked), transcript: transcript) == .noTranscript)
    }

    // MARK: Screen-text note

    @Test(arguments: [TranscriptFeed.State.waiting, .ended])
    func screenTextWithoutASessionSaysNoTranscriptIsLinked(transcript: TranscriptFeed.State) {
        #expect(DetailBody.noChatNote(for: .fake(pane: "w1:p1"), transcript: transcript)
            == "no transcript linked · screen text")
    }

    @Test func screenTextWhileTheTranscriptIsStillLoadingSaysOnlyScreenText() {
        #expect(DetailBody.noChatNote(for: .fake(pane: "w1:p1", session: session), transcript: .waiting)
            == "screen text")
    }

    @Test func screenTextInPlaceOfAnUnreadableTranscriptSaysItIsUnavailable() {
        #expect(DetailBody.noChatNote(for: .fake(pane: "w1:p1", session: session), transcript: .ended)
            == "transcript unavailable · screen text")
    }

    @Test func aDesktopSessionWithoutATranscriptSaysWhy() {
        #expect(DetailBody.noChatNote(for: .desktop("s1"), transcript: .waiting) == "no transcript yet")
        #expect(DetailBody.noChatNote(for: .desktop("s1", transcript: session), transcript: .waiting) == "loading transcript")
        #expect(DetailBody.noChatNote(for: .desktop("s1", transcript: session), transcript: .ended) == "transcript unavailable")
    }

    @Test func chatAndTheBlockedCardCarryNoScreenTextNote() {
        #expect(DetailBody.noChatNote(for: .fake(pane: "w1:p1", session: session), transcript: .available) == nil)
        #expect(DetailBody.noChatNote(for: .fake(pane: "w1:p1", status: .blocked), transcript: .ended) == nil)
    }

    // MARK: Transcript feed

    @Test func transcriptWaitsUntilItsFirstEmission() {
        var feed = TranscriptFeed(session: session)
        #expect(feed.state(for: session) == .waiting)
        feed.receive([])
        #expect(feed.state(for: session) == .available)
    }

    @Test func transcriptThatNeverEmitsShowsScreenTextThenChatOnceItArrives() {
        let agent = AgentSnapshot.fake(pane: "w1:p1", status: .idle, session: session)
        var feed = TranscriptFeed(session: session)
        #expect(DetailBody(agent, transcript: feed.state(for: agent.transcript)) == .screenText)
        feed.receive([ChatBlock(id: "b1", kind: .prompt("hello"), at: nil)])
        #expect(DetailBody(agent, transcript: feed.state(for: agent.transcript)) == .chat(session))
        #expect(feed.blocks.map(\.id) == ["b1"])
    }

    @Test func transcriptWhoseStreamEndsHasEnded() {
        var feed = TranscriptFeed(session: session)
        feed.receive([ChatBlock(id: "b1", kind: .prompt("hello"), at: nil)])
        feed.end()
        #expect(feed.state(for: session) == .ended)
    }

    @Test func transcriptStreamThatEndsBeforeEmittingHasEnded() {
        var feed = TranscriptFeed(session: session)
        feed.end()
        #expect(feed.state(for: session) == .ended)
    }

    @Test func feedForAnotherSessionCountsAsWaiting() {
        var feed = TranscriptFeed(session: session)
        feed.receive([])
        #expect(feed.state(for: AgentSessionRef(kind: .id, value: "other")) == .waiting)
        #expect(feed.state(for: nil) == .waiting)
    }

    // MARK: Screen reads

    @Test func blockedCardReadsTheVisibleScreen() {
        let request = DetailBody.screenRequest(for: .fake(pane: "w1:p1", status: .blocked), transcript: .waiting,
                                               refreshes: 3)
        #expect(request?.source == .visible)
        #expect(request?.agent == .herdr("w1:p1"))
    }

    @Test func screenTextReadsTheRecentUnwrappedText() {
        let request = DetailBody.screenRequest(for: .fake(pane: "w1:p1", status: .idle), transcript: .waiting,
                                               refreshes: 0)
        #expect(request?.source == .recentUnwrapped)
    }

    @Test func chatReadsNoScreen() {
        #expect(DetailBody.screenRequest(for: .fake(pane: "w1:p1", session: session), transcript: .available,
                                         refreshes: 0) == nil)
    }

    @Test(arguments: [TranscriptFeed.State.waiting, .ended])
    func screenTextInPlaceOfATranscriptReadsTheRecentUnwrappedText(transcript: TranscriptFeed.State) {
        let request = DetailBody.screenRequest(for: .fake(pane: "w1:p1", session: session), transcript: transcript,
                                               refreshes: 0)
        #expect(request?.source == .recentUnwrapped)
    }

    @Test func screenTextIsReadAgainWhenTheStatusChanges() {
        let idle = screenRequest(.fake(pane: "w1:p1", status: .idle, stateChangeSeq: 4))
        let working = screenRequest(.fake(pane: "w1:p1", status: .working, stateChangeSeq: 4))
        #expect(idle != working)
    }

    @Test func screenTextIsReadAgainWhenTheStateChangeSequenceMoves() {
        let before = screenRequest(.fake(pane: "w1:p1", status: .idle, stateChangeSeq: 4))
        let after = screenRequest(.fake(pane: "w1:p1", status: .idle, stateChangeSeq: 5))
        #expect(before != after)
    }

    @Test func screenTextIsReadAgainOnRefresh() {
        let agent = AgentSnapshot.fake(pane: "w1:p1", status: .idle)
        #expect(screenRequest(agent, refreshes: 0) != screenRequest(agent, refreshes: 1))
    }

    @Test func blockedQuestionIsReadAgainWhenTheStatusChangesButNotOnRefresh() {
        let first = AgentSnapshot.fake(pane: "w1:p1", status: .blocked, stateChangeSeq: 4)
        let again = AgentSnapshot.fake(pane: "w1:p1", status: .blocked, stateChangeSeq: 6)
        #expect(screenRequest(first) != screenRequest(again))
        #expect(screenRequest(first, refreshes: 0) == screenRequest(first, refreshes: 1))
    }

    private func screenRequest(_ agent: AgentSnapshot, refreshes: Int = 0) -> DetailBody.ScreenRequest? {
        DetailBody.screenRequest(for: agent, transcript: .waiting, refreshes: refreshes)
    }

    // MARK: Destination

    @Test func aHerdrAgentIsReachedInItsTerminal() {
        #expect(PanelController.Destination(of: .fake(pane: "w1:p1")) == .terminal)
    }

    @Test func aDesktopSessionIsReachedInItsDesktopInstance() {
        #expect(PanelController.Destination(of: .desktop("s1")) == .desktop)
    }

    @Test func aDesktopSessionNeedsNoScreenRead() {
        #expect(DetailBody.screenRequest(for: .desktop("s1", status: .blocked), transcript: .waiting, refreshes: 0) == nil)
    }
}
