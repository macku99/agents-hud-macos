import Foundation
import Synchronization
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

/// A store over one `HerdrAgentSource` wired to a `FakeHerdr`, a settable clock, a reconnect delay that returns at once, and a
/// periodic-reload wait that lasts until the test calls `tickReload()`. Both record what they were asked to wait.
/// Agent listings can be held with `holdAgents()` to land a `stop()` or `start()` while one is in flight.
@MainActor
struct HUDStoreHarness {
    let herdr = FakeHerdr()
    let client: HoldableHerdr
    let source: HerdrAgentSource
    let store: HUDStore
    private let clock = Shared(Date(timeIntervalSince1970: 1_000))
    private let delays = Shared<[Duration]>([])
    private let reloadWaits = Shared<[Duration]>([])
    private let reloadTicks = Shared(0)

    init(agents: [AgentInfo] = []) {
        herdr.setAgents(agents)
        client = HoldableHerdr(herdr)
        source = HerdrAgentSource(
            client: client,
            now: { [clock] in clock.value },
            reconnectSleep: { [delays] duration in delays.update { $0.append(duration) } },
            reloadSleep: { [reloadWaits, reloadTicks] duration in
                reloadWaits.update { $0.append(duration) }
                while !Task.isCancelled {
                    var ticked = false
                    reloadTicks.update { ticks in
                        ticked = ticks > 0
                        if ticked { ticks -= 1 }
                    }
                    if ticked { return }
                    try? await Task.sleep(for: .milliseconds(1))
                }
            })
        store = HUDStore(sources: [source], now: { [clock] in clock.value })
    }

    var now: Date { clock.value }
    var reconnectDelays: [Duration] { delays.value }
    /// Every wait the periodic reload started, including the one it may still be in.
    var reloadIntervals: [Duration] { reloadWaits.value }

    /// Ends the current periodic-reload wait, or the next one to start.
    func tickReload() {
        reloadTicks.update { $0 += 1 }
    }

    func advance(by seconds: TimeInterval) {
        clock.update { $0 = $0.addingTimeInterval(seconds) }
    }

    func count(of call: FakeHerdr.Call) -> Int {
        herdr.calls.count { $0 == call }
    }

    func sendCalls() -> [FakeHerdr.Call] {
        herdr.calls.filter { if case .send = $0 { true } else { false } }
    }

    /// Starts the store and waits until it is subscribed to events, so an `emit` cannot be lost.
    func started() async -> HUDStore {
        await store.start()
        await waitUntil("subscribed") { count(of: .events) == 1 }
        return store
    }

    /// Ends the event subscription and waits until the store has reloaded and subscribed again.
    func dropSubscription(expecting subscriptions: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        herdr.finishEvents()
        await waitUntil("subscription \(subscriptions)", sourceLocation: sourceLocation) { count(of: .events) == subscriptions }
    }

    /// Updates herdr's snapshot and lets the store reload it.
    func reload(_ agents: [AgentInfo]) async {
        herdr.setAgents(agents)
        await store.refresh()
    }

    /// `FakeHerdr.waitForSendsInFlight` with a deadline, so a store that never sends fails the test
    /// instead of hanging the run.
    func waitForSendsInFlight(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("\(count) sends are in flight", sourceLocation: sourceLocation) { herdr.sendsInFlight >= count }
    }

    func holdAgents() { client.listings.hold() }
    func releaseAgents() { client.listings.release() }
    func holdFetches() { client.fetches.hold() }
    func releaseFetches() { client.fetches.release() }
    func holdFocuses() { client.focuses.hold() }
    func releaseFocuses() { client.focuses.release() }

    func waitForHeldAgentListings(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("\(count) agent listings are held", sourceLocation: sourceLocation) { client.listings.heldCount >= count }
    }

    func waitForHeldFetches(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("\(count) agent fetches are held", sourceLocation: sourceLocation) { client.fetches.heldCount >= count }
    }

    func waitForHeldFocuses(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("\(count) focus calls are held", sourceLocation: sourceLocation) { client.focuses.heldCount >= count }
    }

    /// Gives the store's tasks time to do something they should not. Everything they would do runs
    /// within a few main-actor turns, so a quarter second leaves a wide margin on a loaded machine.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    func entry(_ pane: String) -> RosterEntry? {
        store.roster.first { $0.id == key(pane) }
    }

    /// How the store names the local herdr's agent in `pane`.
    func key(_ pane: String) -> AgentKey {
        AgentKey(source: source.id, id: pane)
    }

    /// The agent as the store sees it.
    func snapshot(of agent: AgentInfo) -> AgentSnapshot {
        HerdrAgentSource.snapshot(of: agent, on: .local)
    }

    /// The local herdr's connection state.
    var connection: SourceState? {
        store.connections.first { $0.id == source.id }?.state
    }

    func waitUntil(_ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting until \(what)", sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

extension HUDStoreHarness {
    final class Shared<Value: Sendable>: Sendable {
        private let storage: Mutex<Value>
        init(_ value: Value) { storage = Mutex(value) }
        var value: Value { storage.withLock { $0 } }
        func update(_ change: (inout Value) -> Void) { storage.withLock { change(&$0) } }
    }
}

extension HUDStoreHarness {
    /// Forwards to a `FakeHerdr`, except that agent listings, single-agent fetches and focus calls can be
    /// held. A held call reaches the fake only on release, so it answers with the fake's state as it is then.
    final class HoldableHerdr: HerdrClient, Sendable {
        let listings = Gate()
        let fetches = Gate()
        let focuses = Gate()
        private let herdr: FakeHerdr

        init(_ herdr: FakeHerdr) { self.herdr = herdr }

        func agents(on machine: MachineID) async throws(HerdrError) -> [AgentInfo] {
            await listings.pass()
            return try await herdr.agents(on: machine)
        }

        func agent(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) -> AgentInfo {
            await fetches.pass()
            return try await herdr.agent(pane, on: machine)
        }

        func read(_ pane: PaneID, source: ReadSource, lines: Int, on machine: MachineID) async throws(HerdrError) -> String {
            try await herdr.read(pane, source: source, lines: lines, on: machine)
        }

        func focus(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) {
            await focuses.pass()
            try await herdr.focus(pane, on: machine)
        }

        func send(_ text: String, to identity: AgentIdentity) async -> PromptOutcome {
            await herdr.send(text, to: identity)
        }

        func events(on machine: MachineID) -> AsyncThrowingStream<HerdrEvent, any Error> {
            herdr.events(on: machine)
        }
    }

    /// Lets calls through until `hold()`, then keeps them waiting until `release()`.
    final class Gate: Sendable {
        private struct State {
            var holding = false
            var held: [CheckedContinuation<Void, Never>] = []
        }

        private let state = Mutex(State())

        var heldCount: Int { state.withLock { $0.held.count } }

        func hold() { state.withLock { $0.holding = true } }

        func release() {
            let held = state.withLock { state in
                state.holding = false
                defer { state.held.removeAll() }
                return state.held
            }
            held.forEach { $0.resume() }
        }

        func pass() async {
            await withCheckedContinuation { continuation in
                // Checking and queueing under one lock, so a release in between cannot strand the call.
                let holding = state.withLock { state in
                    if state.holding { state.held.append(continuation) }
                    return state.holding
                }
                if !holding { continuation.resume() }
            }
        }
    }
}
