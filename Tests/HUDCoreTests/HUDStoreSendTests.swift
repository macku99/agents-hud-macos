import Foundation
import OSLog
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreSendTests {
    private let pane = PaneID("w1:p1")
    private let key = AgentKey(source: HerdrAgentSource.id(for: .local), id: "w1:p1")

    private func harness(status: AgentStatus = .idle) async -> HUDStoreHarness {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: status), .fake(pane: "w1:p2", status: .idle)])
        await harness.store.start()
        return harness
    }

    @Test func draftsArePerPane() async {
        let harness = await harness()
        defer { harness.store.stop() }

        harness.store.setDraft("first", for: key)
        harness.store.setDraft("second", for: harness.key("w1:p2"))

        #expect(harness.store.draft(for: key) == "first")
        #expect(harness.store.draft(for: harness.key("w1:p2")) == "second")
        #expect(harness.store.draft(for: harness.key("w9:p9")) == "")
    }

    @Test func aDeliveredSendIsSendingWhileInFlightThenClearsTheDraft() async {
        let harness = await harness(status: .done)
        defer { harness.store.stop() }
        harness.store.setDraft("run the tests", for: key)
        harness.herdr.scriptSend(.delivered)
        harness.herdr.holdSends()

        let sending = Task { await harness.store.send(for: key) }
        await harness.waitForSendsInFlight(1)
        #expect(harness.store.sendState(for: key) == .sending)
        harness.herdr.releaseSends()
        await sending.value

        #expect(harness.store.sendState(for: key) == .ready)
        #expect(harness.store.draft(for: key) == "")
        #expect(harness.sendCalls() == [.send("run the tests", AgentInfo.fake(pane: "w1:p1", status: .done).identity)])
    }

    @Test func aDraftEditedDuringTheSendIsKept() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("first", for: key)
        harness.herdr.scriptSend(.delivered)
        harness.herdr.holdSends()

        let sending = Task { await harness.store.send(for: key) }
        await harness.waitForSendsInFlight(1)
        harness.store.setDraft("first and more", for: key)
        harness.herdr.releaseSends()
        await sending.value

        #expect(harness.store.draft(for: key) == "first and more")
        #expect(harness.store.sendState(for: key) == .ready)
    }

    @Test func aRefusedSendKeepsTheDraftAndIsNotRetried() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.refused(.agentChanged), .delivered)

        await harness.store.send(for: key)
        await Task.yield()

        #expect(harness.store.sendState(for: key) == .refused(.agentChanged))
        #expect(harness.store.draft(for: key) == "hello")
        #expect(harness.sendCalls().count == 1)
    }

    @Test func aRefusedSendMaySendAgain() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.refused(.notReady(.working)), .delivered)
        await harness.store.send(for: key)

        await harness.store.send(for: key)

        #expect(harness.sendCalls().count == 2)
        #expect(harness.store.sendState(for: key) == .ready)
    }

    @Test func editingTheDraftOrSelectingTheAgentClearsARefusal() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.refused(.rejected("agent_blocked")), .refused(.rejected("agent_blocked")))

        await harness.store.send(for: key)
        harness.store.setDraft("hello there", for: key)
        #expect(harness.store.sendState(for: key) == .ready)

        await harness.store.send(for: key)
        harness.store.select(key)
        #expect(harness.store.sendState(for: key) == .ready)
    }

    @Test func theSendLogNamesOutcomesAndStatesButNotHerdrsText() async throws {
        let pane = PaneID("w9:p\(UInt32.random(in: 1...UInt32.max))")
        let harness = HUDStoreHarness(agents: [.fake(pane: pane.rawValue, status: .idle)])
        let key = harness.key(pane.rawValue)
        await harness.store.start()
        defer { harness.store.stop() }
        let detail = "herdr-detail-marker-\(UUID().uuidString)"
        harness.store.setDraft("prompt-marker", for: key)
        harness.herdr.scriptSend(.uncertain(detail))

        await harness.store.send(for: key)
        await harness.store.send(for: key)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "app.itfrombit.agentshud" && $0.category == "send" }
            .map(\.composedMessage)
        #expect(messages.contains { $0.contains("send to \(pane.rawValue) ended: uncertain") })
        #expect(messages.contains { $0.contains("send to \(pane.rawValue) skipped: a send is uncertain") })
        #expect(!messages.contains { $0.contains(detail) })
        #expect(!messages.contains { $0.contains("prompt-marker") })
    }

    @Test func anUncertainSendBlocksSendingUntilReconciled() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("deploy", for: key)
        harness.herdr.scriptSend(.uncertain("socket closed"), .delivered)

        await harness.store.send(for: key)
        #expect(harness.store.sendState(for: key) == .uncertain("socket closed"))
        #expect(harness.store.draft(for: key) == "deploy")

        await harness.store.send(for: key)
        harness.store.setDraft("deploy now", for: key)
        await harness.store.send(for: key)
        #expect(harness.sendCalls().count == 1)
        #expect(harness.store.sendState(for: key) == .uncertain("socket closed"))

        harness.store.reconcile(key)
        #expect(harness.store.sendState(for: key) == .ready)
        await harness.store.send(for: key)
        #expect(harness.sendCalls().count == 2)
        #expect(harness.store.sendState(for: key) == .ready)
    }

    @Test func reconcileLeavesARefusalAlone() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.refused(.agentChanged))
        await harness.store.send(for: key)

        harness.store.reconcile(key)

        #expect(harness.store.sendState(for: key) == .refused(.agentChanged))
    }

    @Test(arguments: [AgentStatus.working, .blocked, .unknown])
    func anAgentThatCannotTakeAPromptGetsNoSend(status: AgentStatus) async {
        let harness = await harness(status: status)
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)

        await harness.store.send(for: key)

        #expect(harness.sendCalls().isEmpty)
        #expect(harness.store.sendState(for: key) == .ready)
    }

    @Test func anEmptyDraftOrAnUnknownPaneGetsNoSend() async {
        let harness = await harness()
        defer { harness.store.stop() }

        await harness.store.send(for: key)
        harness.store.setDraft("hello", for: harness.key("w9:p9"))
        await harness.store.send(for: harness.key("w9:p9"))

        #expect(harness.sendCalls().isEmpty)
    }

    @Test func aDraftOfOnlyWhitespaceGetsNoSend() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft(" \n\t ", for: key)

        await harness.store.send(for: key)

        #expect(harness.sendCalls().isEmpty)
    }

    @Test func aSecondSendWaitsUntilTheFirstHasReturned() async {
        let harness = await harness()
        defer { harness.store.stop() }
        let otherKey = harness.key("w1:p2")
        harness.store.setDraft("first", for: key)
        harness.store.setDraft("second", for: otherKey)
        harness.herdr.scriptSend(.delivered, .delivered)
        harness.herdr.holdSends()

        let first = Task { await harness.store.send(for: key) }
        await harness.waitForSendsInFlight(1)
        let second = Task { await harness.store.send(for: otherKey) }
        await harness.waitUntil("the second send is queued") { harness.store.sendState(for: otherKey) == .sending }
        for _ in 0..<20 { await Task.yield() }
        #expect(harness.herdr.sendsInFlight == 1)
        #expect(harness.sendCalls().count == 1)

        harness.herdr.releaseSends()
        await first.value
        await second.value

        #expect(harness.sendCalls().map { call in
            if case .send(let text, _) = call { text } else { "" }
        } == ["first", "second"])
        #expect(harness.store.sendState(for: otherKey) == .ready)
        #expect(harness.store.draft(for: otherKey) == "")
    }

    @Test func twoQuickSendsForOneAgentSendOnce() async {
        let harness = await harness()
        defer { harness.store.stop() }
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.delivered, .delivered)
        harness.herdr.holdSends()

        let first = Task { await harness.store.send(for: key) }
        let second = Task { await harness.store.send(for: key) }
        await harness.waitForSendsInFlight(1)
        await harness.settle()
        harness.herdr.releaseSends()
        await first.value
        await second.value
        await harness.settle()

        #expect(harness.sendCalls().count == 1)
    }

    @Test func aQueuedSendGoesToTheIdentityTheUserSentTo() async {
        let harness = await harness()
        defer { harness.store.stop() }
        let otherKey = harness.key("w1:p2")
        harness.store.setDraft("first", for: otherKey)
        harness.store.setDraft("second", for: key)
        harness.herdr.scriptSend(.delivered, .delivered)
        harness.herdr.holdSends()
        let picked = AgentInfo.fake(pane: "w1:p1", status: .idle).identity

        let first = Task { await harness.store.send(for: otherKey) }
        await harness.waitForSendsInFlight(1)
        let second = Task { await harness.store.send(for: key) }
        await harness.waitUntil("the second send is queued") { harness.store.sendState(for: key) == .sending }
        let replaced = AgentInfo.fake(pane: "w1:p1", status: .idle, session: AgentSessionRef(kind: .id, value: "other-session"))
        await harness.reload([replaced, .fake(pane: "w1:p2", status: .idle)])
        harness.herdr.releaseSends()
        await first.value
        await second.value

        #expect(harness.sendCalls().last == .send("second", picked))
    }

    @Test func aSendGoesToTheAgentsCurrentIdentity() async {
        let harness = await harness()
        defer { harness.store.stop() }
        let resumed = AgentInfo.fake(pane: "w1:p1", status: .idle, session: AgentSessionRef(kind: .id, value: "session-2"))
        await harness.reload([resumed])
        harness.store.setDraft("hello", for: key)
        harness.herdr.scriptSend(.delivered)

        await harness.store.send(for: key)

        #expect(harness.sendCalls() == [.send("hello", resumed.identity)])
    }
}
