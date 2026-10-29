import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreRosterTests {
    @Test func startLoadsTheRosterAndConnects() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])
        let store = await harness.started()
        defer { store.stop() }

        #expect(harness.connection == .connected)
        #expect(store.roster.map(\.id) == [harness.key("w1:p1"), harness.key("w1:p2")])
        #expect(harness.herdr.calls.first == .agents)
    }

    @Test func startWithoutHerdrIsUnavailableWithAnEmptyRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.herdr.failNext(.agents, with: .unreachable("no socket"))
        let store = await harness.started()
        defer { store.stop() }

        #expect(harness.connection == .unavailable("herdr is not reachable"))
        #expect(store.roster.isEmpty)
    }

    @Test func refreshListsTheAgentsAgain() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1"), .fake(pane: "w2:p1")])

        #expect(harness.store.roster.map(\.id) == [harness.key("w1:p1"), harness.key("w2:p1")])
    }

    @Test func aFailedRefreshKeepsTheRosterAndItsTimers() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        defer { harness.store.stop() }
        let firstSight = harness.now
        harness.advance(by: 30)

        harness.herdr.failNext(.agents, with: .timedOut)
        await harness.store.refresh()
        #expect(harness.connection == .unavailable("herdr is not responding"))
        #expect(harness.store.roster.map(\.id) == [harness.key("w1:p1")])
        #expect(harness.entry("w1:p1")?.stateSince == firstSight)

        await harness.store.refresh()
        #expect(harness.connection == .connected)
        #expect(harness.entry("w1:p1")?.stateSince == firstSight)
    }

    @Test func aRestartWhoseFirstLoadFailsLeavesTheRosterEmpty() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        harness.store.stop()
        harness.herdr.failNext(.agents, with: .unreachable("gone"))

        await harness.store.start()
        defer { harness.store.stop() }

        #expect(harness.connection == .unavailable("herdr is not reachable"))
        #expect(harness.store.roster.isEmpty)
    }

    @Test func aFailedPeriodicReloadKeepsTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        defer { store.stop() }
        await harness.waitUntil("the reload waits") { harness.reloadIntervals.count == 1 }
        harness.herdr.failNext(.agents, with: .timedOut)

        harness.tickReload()

        await harness.waitUntil("the reload fails") { harness.connection == .unavailable("herdr is not responding") }
        #expect(store.roster.count == 1)
    }

    @Test func attentionComesFirstThenWorkingThenTheRestInHerdrsOrder() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "idle-1", status: .idle),
            .fake(pane: "working-1", status: .working),
            .fake(pane: "blocked", status: .blocked),
            .fake(pane: "unknown", status: .unknown),
            .fake(pane: "done", status: .done, completionSeq: 1),
            .fake(pane: "working-2", status: .working),
            .fake(pane: "idle-2", status: .idle),
        ])
        await harness.store.start()
        defer { harness.store.stop() }

        #expect(harness.store.roster.map(\.id.id) == ["blocked", "done", "working-1", "working-2", "idle-1", "unknown", "idle-2"])
    }

    @Test func stateSinceIsWhenTheStoreFirstSawTheCurrentStatus() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle), .fake(pane: "w1:p2", status: .idle)])
        await harness.store.start()
        defer { harness.store.stop() }
        let firstSight = harness.now
        #expect(harness.entry("w1:p1")?.stateSince == firstSight)

        harness.advance(by: 30)
        await harness.reload([.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .idle)])

        #expect(harness.entry("w1:p1")?.stateSince == harness.now)
        #expect(harness.entry("w1:p2")?.stateSince == firstSight)
    }

    @Test func aNewAgentInAReusedPaneGetsAFreshStateSince() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.advance(by: 30)

        await harness.reload([.fake(pane: "w1:p1", status: .idle, agent: "codex")])

        #expect(harness.entry("w1:p1")?.stateSince == harness.now)
    }

    @Test func badgeCountsBlockedAndUnseenAgents() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "blocked", status: .blocked),
            .fake(pane: "done", status: .done, completionSeq: 4),
            .fake(pane: "working", status: .working),
            .fake(pane: "idle", status: .idle),
        ])
        await harness.store.start()
        defer { harness.store.stop() }

        #expect(harness.store.badgeCount == 2)
        #expect(harness.entry("blocked")?.attention == .blocked)
        #expect(harness.entry("done")?.attention == .unseen)
        #expect(harness.entry("working")?.attention == Attention.none)
    }

    @Test func anyAgentWorkingFollowsTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        #expect(harness.store.isAnyAgentWorking)

        await harness.reload([.fake(pane: "w1:p1", status: .idle)])
        #expect(!harness.store.isAnyAgentWorking)
    }
}
