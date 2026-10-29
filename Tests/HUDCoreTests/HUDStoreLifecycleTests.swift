import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreLifecycleTests {
    @Test func stopDuringTheFirstLoadStartsNothing() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.holdAgents()

        let starting = Task { await harness.store.start() }
        await harness.waitForHeldAgentListings(1)
        harness.store.stop()
        harness.releaseAgents()
        await starting.value
        await harness.settle()

        #expect(harness.count(of: .events) == 0)
        #expect(harness.reloadIntervals.isEmpty)
        #expect(harness.store.roster.isEmpty)
    }

    @Test func aSecondStartReplacesOneStillLoading() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        harness.holdAgents()

        let first = Task { await harness.store.start() }
        await harness.waitForHeldAgentListings(1)
        let second = Task { await harness.store.start() }
        await harness.waitForHeldAgentListings(2)
        harness.releaseAgents()
        await first.value
        await second.value
        await harness.settle()
        defer { harness.store.stop() }

        #expect(harness.count(of: .events) == 1)
        #expect(harness.reloadIntervals.count == 1)
        #expect(harness.store.roster.count == 1)
        #expect(harness.connection == .connected)
    }

    @Test func aListingLandingAfterStopIsIgnored() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        await heldUnhideReload(harness)
        harness.herdr.setAgents([.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])

        store.stop()
        harness.releaseAgents()
        await harness.settle()

        #expect(store.roster.count == 1)
    }

    @Test func aFailedListingLandingAfterStopIsIgnored() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        await heldUnhideReload(harness)
        harness.herdr.failNext(.agents, with: .timedOut)

        store.stop()
        harness.releaseAgents()
        await harness.settle()

        #expect(harness.connection == .connected)
        #expect(store.roster.count == 1)
    }

    @Test func anUnhideReloadNotYetStartedWhenStoppedChangesNothing() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        let store = await harness.started()
        harness.herdr.setAgents([.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])

        store.toggleHUD()
        store.toggleHUD()
        store.stop()
        await harness.settle()

        #expect(store.roster.count == 1)
    }

    @Test func aFetchLandingAfterStopIsIgnored() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle)])
        let store = await harness.started()
        harness.holdFetches()
        harness.herdr.emit(.agentStatusChanged(PaneID("w1:p1"), .working))
        await harness.waitForHeldFetches(1)
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .working, stateChangeSeq: 2)])

        store.stop()
        harness.releaseFetches()
        await harness.waitUntil("the fetch reaches herdr") { harness.count(of: .agent(PaneID("w1:p1"))) == 1 }
        await harness.settle()

        #expect(harness.entry("w1:p1")?.agent.status == .idle)
    }

    @Test func aFetchFailingAfterStopReloadsNothing() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle)])
        let store = await harness.started()
        harness.holdFetches()
        harness.herdr.emit(.agentStatusChanged(PaneID("w1:p1"), .working))
        await harness.waitForHeldFetches(1)
        harness.herdr.failNext(.agent, with: .timedOut)

        store.stop()
        harness.releaseFetches()
        await harness.waitUntil("the fetch reaches herdr") { harness.count(of: .agent(PaneID("w1:p1"))) == 1 }
        await harness.settle()

        #expect(harness.count(of: .agents) == 1)
    }

    @Test func aFocusFailingAfterStopReloadsNothing() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle)])
        let store = await harness.started()
        harness.holdFocuses()
        harness.herdr.failNext(.focus, with: .unreachable("no socket"))
        let focusing = Task { await store.focus(harness.key("w1:p1")) }
        await harness.waitForHeldFocuses(1)

        store.stop()
        harness.releaseFocuses()
        await focusing.value
        await harness.settle()

        #expect(harness.count(of: .focus(PaneID("w1:p1"))) == 1)
        #expect(harness.count(of: .agents) == 1)
    }

    @Test func eventsBufferedBeforeStopAreNotHandled() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .idle)])
        let store = await harness.started()
        harness.holdAgents()
        harness.herdr.emit(.agentStatusChanged(PaneID("w9:p9"), .working))
        await harness.waitForHeldAgentListings(1)
        harness.herdr.emit(.agentStatusChanged(PaneID("w1:p1"), .working))
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .working, stateChangeSeq: 2)])

        store.stop()
        harness.releaseAgents()
        await harness.waitUntil("the held listing reaches herdr") { harness.count(of: .agents) == 2 }
        await harness.settle()

        #expect(harness.count(of: .agent(PaneID("w1:p1"))) == 0)
        #expect(harness.entry("w1:p1")?.agent.status == .idle)
    }

    /// Hides and shows the HUD, leaving the reload that showing it starts held.
    private func heldUnhideReload(_ harness: HUDStoreHarness) async {
        harness.holdAgents()
        harness.store.toggleHUD()
        harness.store.toggleHUD()
        await harness.waitForHeldAgentListings(1)
    }
}
