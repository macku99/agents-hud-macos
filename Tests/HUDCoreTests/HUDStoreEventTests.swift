import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreEventTests {
    private let pane = PaneID("w1:p1")
    private let key = AgentKey(source: HerdrAgentSource.id(for: .local), id: "w1:p1")

    @Test func aStatusEventRefetchesThatAgent() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle), .fake(pane: "w1:p2", status: .idle)])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .working, stateChangeSeq: 2), .fake(pane: "w1:p2", status: .working)])

        harness.herdr.emit(.agentStatusChanged(pane, .working))

        await harness.waitUntil("the agent is working") { harness.entry("w1:p1")?.agent.status == .working }
        #expect(harness.entry("w1:p1")?.agent.herdr?.stateChangeSeq == 2)
        #expect(harness.entry("w1:p2")?.agent.status == .idle)
        #expect(harness.count(of: .agent(pane)) == 1)
        #expect(harness.count(of: .agents) == 1)
    }

    @Test func aFetchOlderThanTheRosterIsDropped() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "w1:p1", status: .working, stateChangeSeq: 5),
            .fake(pane: "w1:p2", status: .idle, stateChangeSeq: 1),
        ])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([
            .fake(pane: "w1:p1", status: .idle, stateChangeSeq: 4),
            .fake(pane: "w1:p2", status: .working, stateChangeSeq: 2),
        ])

        harness.herdr.emit(.agentStatusChanged(pane, .idle))
        harness.herdr.emit(.agentStatusChanged(PaneID("w1:p2"), .working))

        await harness.waitUntil("the later event is handled") { harness.entry("w1:p2")?.agent.status == .working }
        #expect(harness.entry("w1:p1")?.agent.status == .working)
        #expect(harness.entry("w1:p1")?.agent.herdr?.stateChangeSeq == 5)
    }

    @Test func aFetchOfANewAgentInThePaneIsKeptWhateverItsSequence() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working, stateChangeSeq: 5)])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .idle, agent: "codex", stateChangeSeq: 1)])

        harness.herdr.emit(.agentStatusChanged(pane, .idle))

        await harness.waitUntil("the new agent replaces the old one") { harness.entry("w1:p1")?.agent.kind == "codex" }
    }

    @Test func aStatusEventCanRaiseAnAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .blocked)])

        harness.herdr.emit(.agentStatusChanged(pane, .blocked))

        await harness.waitUntil("an alert") { !store.alerts.isEmpty }
        #expect(store.alerts.map(\.kind) == [.needsInput])
    }

    @Test func anEventForAnUnknownPaneRefreshesTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([.fake(pane: "w1:p1"), .fake(pane: "w2:p1", status: .working)])

        harness.herdr.emit(.agentStatusChanged(PaneID("w2:p1"), .working))

        await harness.waitUntil("the new agent is listed") { store.roster.count == 2 }
        #expect(harness.count(of: .agents) == 2)
        #expect(harness.count(of: .agent(PaneID("w2:p1"))) == 0)
    }

    @Test func anAgentThatCannotBeFetchedRefreshesTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.failNext(.agent, with: .timedOut)

        harness.herdr.emit(.agentStatusChanged(pane, .working))

        await harness.waitUntil("a refresh") { harness.count(of: .agents) == 2 }
        #expect(harness.connection == .connected)
    }

    @Test func whenTheStreamEndsTheStoreRefreshesThenSubscribesAgain() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        harness.herdr.setAgents([.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])

        harness.herdr.finishEvents()

        await harness.waitUntil("subscribed again") { harness.count(of: .events) == 2 }
        #expect(harness.reconnectDelays == [.seconds(1)])
        #expect(Array(harness.herdr.calls.suffix(2)) == [.agents, .events])
        // The reload reaches the store on the source's stream, which may be a turn after the resubscribe.
        await harness.waitUntil("the reload lands") { store.roster.count == 2 }

        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2")])
        harness.herdr.emit(.agentStatusChanged(pane, .working))
        await harness.waitUntil("the new subscription delivers") { harness.entry("w1:p1")?.agent.status == .working }
    }

    @Test func whenTheStreamThrowsTheStoreSubscribesAgain() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }

        harness.herdr.finishEvents(throwing: HerdrError.unreachable("socket closed"))

        await harness.waitUntil("subscribed again") { harness.count(of: .events) == 2 }
        #expect(harness.count(of: .agents) == 2)
    }

    @Test func aSubscriptionThatKeepsEndingBacksOffByDoublingUpToThirtySeconds() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }

        for subscriptions in 2...8 {
            await harness.dropSubscription(expecting: subscriptions)
        }

        #expect(harness.reconnectDelays == [1, 2, 4, 8, 16, 30, 30].map { .seconds($0) })
        #expect(harness.connection == .connected)
    }

    @Test func aSubscriptionOpenForThirtySecondsResetsTheBackoff() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        await harness.dropSubscription(expecting: 2)
        await harness.dropSubscription(expecting: 3)

        harness.advance(by: 30)
        await harness.dropSubscription(expecting: 4)
        await harness.dropSubscription(expecting: 5)

        #expect(harness.reconnectDelays == [1, 2, 1, 2].map { .seconds($0) })
    }

    @Test func anEventResetsTheBackoff() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        await harness.dropSubscription(expecting: 2)
        await harness.dropSubscription(expecting: 3)

        harness.herdr.emit(.agentStatusChanged(pane, .idle))
        await harness.waitUntil("the event is handled") { harness.count(of: .agent(pane)) == 1 }
        await harness.dropSubscription(expecting: 4)
        await harness.dropSubscription(expecting: 5)

        #expect(harness.reconnectDelays == [1, 2, 1, 2].map { .seconds($0) })
    }

    @Test func stopEndsTheSubscription() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()

        store.stop()
        harness.herdr.emit(.agentStatusChanged(pane, .working))
        harness.herdr.finishEvents()
        await harness.settle()

        #expect(harness.herdr.calls == [.agents, .events])
        #expect(harness.reconnectDelays.isEmpty)
    }

    @Test func stopDuringAReconnectReloadDoesNotSubscribeAgain() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        harness.holdAgents()

        harness.herdr.finishEvents()
        await harness.waitForHeldAgentListings(1)
        store.stop()
        harness.releaseAgents()
        await harness.settle()

        #expect(harness.count(of: .events) == 1)
    }

    @Test func aClosedPaneLeavesTheRosterAfterOneReloadInterval() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])
        let store = await harness.started()
        defer { store.stop() }
        await harness.waitUntil("the reload waits") { harness.reloadIntervals.count == 1 }
        harness.herdr.setAgents([.fake(pane: "w1:p1")])

        harness.tickReload()

        await harness.waitUntil("the closed key is gone") { store.roster.map(\.id) == [key] }
        await harness.waitUntil("the next reload waits") { harness.reloadIntervals.count == 2 }
        #expect(harness.reloadIntervals == [.seconds(30), .seconds(30)])
        #expect(harness.count(of: .agents) == 2)
    }

    @Test func stopEndsThePeriodicReloads() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        await harness.waitUntil("the reload waits") { harness.reloadIntervals.count == 1 }

        store.stop()
        harness.tickReload()
        await harness.settle()

        #expect(harness.count(of: .agents) == 1)
    }

    @Test func focusAsksHerdrToFocusThePane() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.store.focus(key)

        #expect(harness.count(of: .focus(pane)) == 1)
        #expect(harness.count(of: .agents) == 1)
    }

    @Test func aFailedFocusKeepsTheStateAndRefreshes() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 1)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.herdr.failNext(.focus, with: .unreachable("no socket"))

        await harness.store.focus(key)

        #expect(harness.count(of: .focus(pane)) == 1)
        #expect(harness.count(of: .agents) == 2)
        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }

    @Test func aFailedFocusWhoseReloadAlsoFailsKeepsTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.herdr.failNext(.focus, with: .unreachable("no socket"))
        harness.herdr.failNext(.agents, with: .unreachable("no socket"))

        await harness.store.focus(key)

        #expect(harness.connection == .unavailable("herdr is not reachable"))
        #expect(harness.store.roster.count == 1)
    }

    @Test func screenTextReadsMoreLinesForRecentTextThanForTheVisibleScreen() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.herdr.setScreen("synthetic screen", for: pane)

        let recent = await harness.store.screenText(for: key, source: .recentUnwrapped)
        let visible = await harness.store.screenText(for: key, source: .visible)

        #expect(recent == "synthetic screen")
        #expect(visible == "synthetic screen")
        #expect(harness.herdr.calls == [.read(pane, .recentUnwrapped, 180), .read(pane, .visible, 40)])
    }

    @Test func screenTextIsNilWhenHerdrCannotBeRead() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.herdr.setScreen("synthetic screen", for: pane)
        harness.herdr.failNext(.read, with: .outputTooLarge)

        let text = await harness.store.screenText(for: key, source: .visible)

        #expect(text == nil)
    }

    @Test func recentTextFallsBackToTheVisibleScreenWhileTheAgentWorks() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        harness.herdr.setScreen("synthetic screen", for: pane)
        harness.herdr.failNext(.read, with: .rejected(code: "agent_not_idle", message: "cannot read 180 lines while working"))

        let text = await harness.store.screenText(for: key, source: .recentUnwrapped)

        #expect(text == "synthetic screen")
        #expect(harness.herdr.calls == [.read(pane, .recentUnwrapped, 180), .read(pane, .visible, 40)])
    }

    @Test func otherReadRejectionsDoNotFallBack() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.herdr.setScreen("synthetic screen", for: pane)
        harness.herdr.failNext(.read, with: .rejected(code: "not_found", message: "pane not found"))

        let text = await harness.store.screenText(for: key, source: .recentUnwrapped)

        #expect(text == nil)
        #expect(harness.herdr.calls == [.read(pane, .recentUnwrapped, 180)])
    }
}
