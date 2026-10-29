import Foundation
import Testing
import HerdrKit
@testable import HUDCore

@Suite @MainActor struct HUDStoreSourcesTests {
    private let first = FakeAgentSource("first")
    private let second = FakeAgentSource("second")

    private func started() async -> HUDStore {
        let store = HUDStore(sources: [first, second])
        await store.start()
        return store
    }

    private func waitUntil(_ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting until \(what)", sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func startReturnsWithEverySourcesFirstRosterMerged() async {
        first.publish([first.agent("a"), first.agent("b")])
        second.publish([second.agent("c")])
        let store = await started()
        defer { store.stop() }

        #expect(store.roster.map(\.id.id) == ["a", "b", "c"])
        #expect(store.connections.map(\.state) == [.connected, .connected])
    }

    @Test func aStopBeforeTheSourcesStartLeavesNoneRunning() async {
        let store = HUDStore(sources: [first, second])

        let starting = Task { await store.start() }
        await Task.yield()
        store.stop()
        await starting.value
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!first.isRunning)
        #expect(!second.isRunning)
    }

    @Test func aStartReplacingAnotherBeforeItsSourcesStartKeepsReceivingRosters() async {
        let store = HUDStore(sources: [first, second])

        let earlier = Task { await store.start() }
        await Task.yield()
        await store.start()
        await earlier.value
        defer { store.stop() }
        first.publish([first.agent("late")])

        await waitUntil("the latest start receives rosters") { store.roster.contains { $0.id.id == "late" } }
    }

    @Test func oneSourcesChangeLeavesTheOthersAgentsInPlace() async {
        first.publish([first.agent("a")])
        second.publish([second.agent("c")])
        let store = await started()
        defer { store.stop() }

        first.publish([first.agent("a", .working), first.agent("b")])

        await waitUntil("the first source's change lands") { store.roster.count == 3 }
        #expect(store.roster.map(\.id.id) == ["a", "b", "c"])
        #expect(store.isAnyAgentWorking)
    }

    @Test func anOlderSnapshotArrivingLateIsDropped() async {
        first.publish([first.agent("a")])
        let store = await started()
        defer { store.stop() }

        let newer = first.publish([first.agent("a", .working)])
        first.publish([first.agent("a", .idle), first.agent("stale")], revision: newer.revision - 1)

        await waitUntil("the newer snapshot lands") { store.isAnyAgentWorking }
        // Everything the store would do with the late snapshot happens within a few main-actor turns.
        try? await Task.sleep(for: .milliseconds(250))
        #expect(store.roster.map(\.id.id) == ["a"])
        #expect(store.roster.first?.agent.status == .working)
    }

    @Test func aRefreshIsAppliedBeforeItReturns() async {
        let store = await started()
        defer { store.stop() }
        first.setAgents([first.agent("a")])

        await store.refresh()

        #expect(first.refreshCount == 1)
        #expect(second.refreshCount == 1)
        #expect(store.roster.map(\.id.id) == ["a"])
    }

    @Test func eachSourcesConnectionIsKeptApart() async {
        first.publish([first.agent("a")])
        second.publish([second.agent("c")])
        let store = await started()
        defer { store.stop() }

        second.publish([second.agent("c")], state: .unavailable("second is gone"), isFullListing: false)

        await waitUntil("the second source is unavailable") { store.connections.last?.state == .unavailable("second is gone") }
        #expect(store.connections.first?.state == .connected)
        #expect(store.roster.map(\.id.id) == ["a", "c"])
    }

    @Test func aSourceHoldsItsAlertsUntilItsOwnNextFullListing() async {
        first.publish([first.agent("a", .working)])
        second.publish([second.agent("c", .working)])
        let store = await started()
        defer { store.stop() }
        second.answersRefresh = false
        store.toggleHUD()
        store.toggleHUD()
        await waitUntil("both sources refreshed after unhide") { first.refreshCount == 1 && second.refreshCount == 1 }

        // Only the first source has answered with a full listing since the unhide.
        second.publish([second.agent("c", .working)], isFullListing: false)
        second.publish([second.agent("c", .blocked)], isFullListing: false)
        first.publish([first.agent("a", .blocked)], isFullListing: false)

        await waitUntil("both changes land") { store.roster.allSatisfy { $0.agent.status == .blocked } }
        #expect(store.alerts.map(\.key.id) == ["a"])
    }
}
