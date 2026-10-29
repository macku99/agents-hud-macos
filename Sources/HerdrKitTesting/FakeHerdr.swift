import HerdrKit
import Synchronization

/// A scriptable `HerdrClient` for tests. It never talks to a real herdr, so tests can never
/// prompt a real agent.
public final class FakeHerdr: HerdrClient, Sendable {
    public enum Call: Hashable, Sendable {
        case agents
        case agent(PaneID)
        case read(PaneID, ReadSource, Int)
        case focus(PaneID)
        case send(String, AgentIdentity)
        case events
    }

    /// Calls whose next invocation can be scripted to throw.
    public enum Operation: Hashable, Sendable {
        case agents, agent, read, focus
    }

    private struct State {
        var calls: [Call] = []
        var snapshot: [AgentInfo] = []
        var failures: [Operation: [HerdrError]] = [:]
        var sendOutcomes: [PromptOutcome] = []
        var screens: [PaneID: String] = [:]
        var holdingSends = false
        var heldSends: [CheckedContinuation<Void, Never>] = []
        var sendsInFlight = 0
        var eventContinuation: AsyncThrowingStream<HerdrEvent, any Error>.Continuation?
    }

    private let state = Mutex(State())

    public init() {}

    // MARK: Scripting

    public var calls: [Call] { state.withLock { $0.calls } }
    /// Sends that have started and not yet returned.
    public var sendsInFlight: Int { state.withLock { $0.sendsInFlight } }

    public func setAgents(_ agents: [AgentInfo]) { state.withLock { $0.snapshot = agents } }
    public func failNext(_ operation: Operation, with error: HerdrError) {
        state.withLock { $0.failures[operation, default: []].append(error) }
    }
    public func scriptSend(_ outcomes: PromptOutcome...) { state.withLock { $0.sendOutcomes.append(contentsOf: outcomes) } }
    public func setScreen(_ text: String, for pane: PaneID) { state.withLock { $0.screens[pane] = text } }

    /// Sends started from now on wait until `releaseSends()`, so a test can observe them in flight.
    public func holdSends() { state.withLock { $0.holdingSends = true } }
    public func releaseSends() {
        let held = state.withLock { state in
            state.holdingSends = false
            defer { state.heldSends.removeAll() }
            return state.heldSends
        }
        held.forEach { $0.resume() }
    }

    public func waitForSendsInFlight(_ count: Int) async {
        while sendsInFlight < count { await Task.yield() }
    }

    /// Delivers `event` to the current subscriber, if any.
    public func emit(_ event: HerdrEvent) { _ = state.withLock { $0.eventContinuation }?.yield(event) }
    /// Ends the current subscription; a later `events(on:)` starts a new one.
    public func finishEvents(throwing error: (any Error)? = nil) {
        let continuation = state.withLock { state in
            defer { state.eventContinuation = nil }
            return state.eventContinuation
        }
        continuation?.finish(throwing: error)
    }

    // MARK: HerdrClient

    public func agents(on machine: MachineID) async throws(HerdrError) -> [AgentInfo] {
        try record(.agents, failing: .agents)
        return state.withLock { $0.snapshot }
    }

    public func agent(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) -> AgentInfo {
        try record(.agent(pane), failing: .agent)
        guard let match = state.withLock({ $0.snapshot.first { $0.paneID == pane } }) else {
            throw HerdrError.rejected(code: "agent_not_found", message: pane.rawValue)
        }
        return match
    }

    public func read(_ pane: PaneID, source: ReadSource, lines: Int, on machine: MachineID) async throws(HerdrError) -> String {
        try record(.read(pane, source, lines), failing: .read)
        return state.withLock { $0.screens[pane] ?? "" }
    }

    public func focus(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) {
        try record(.focus(pane), failing: .focus)
    }

    public func send(_ text: String, to identity: AgentIdentity) async -> PromptOutcome {
        let holding = state.withLock { state in
            state.calls.append(.send(text, identity))
            state.sendsInFlight += 1
            return state.holdingSends
        }
        if holding {
            await withCheckedContinuation { continuation in
                // releaseSends() may already have run between the check above and here.
                let stillHolding = state.withLock { state in
                    if state.holdingSends { state.heldSends.append(continuation) }
                    return state.holdingSends
                }
                if !stillHolding { continuation.resume() }
            }
        }
        return state.withLock { state in
            state.sendsInFlight -= 1
            guard !state.sendOutcomes.isEmpty else { return .uncertain("FakeHerdr: no send outcome scripted") }
            return state.sendOutcomes.removeFirst()
        }
    }

    public func events(on machine: MachineID) -> AsyncThrowingStream<HerdrEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: HerdrEvent.self, throwing: (any Error).self)
        let previous = state.withLock { state in
            state.calls.append(.events)
            defer { state.eventContinuation = continuation }
            return state.eventContinuation
        }
        previous?.finish()
        return stream
    }

    private func record(_ call: Call, failing operation: Operation) throws(HerdrError) {
        let failure = state.withLock { state -> HerdrError? in
            state.calls.append(call)
            guard var queued = state.failures[operation], !queued.isEmpty else { return nil }
            let next = queued.removeFirst()
            state.failures[operation] = queued
            return next
        }
        if let failure { throw failure }
    }
}

extension AgentInfo {
    /// A local agent whose other ids derive from `pane`, so two fakes differ only where a test says so.
    public static func fake(pane: String, status: AgentStatus = .idle, title: String? = nil, agent: String = "claude",
                            cwd: String? = nil, completionSeq: UInt64? = nil, stateChangeSeq: UInt64 = 1,
                            session: AgentSessionRef? = nil) -> AgentInfo {
        let workspace = String(pane.split(separator: ":").first ?? Substring(pane))
        return AgentInfo(machine: .local, paneID: PaneID(pane), terminalID: "term-\(pane)", workspaceID: workspace,
                         tabID: "\(workspace):t1", agent: agent, status: status, title: title ?? pane, cwd: cwd,
                         completionSeq: completionSeq, stateChangeSeq: stateChangeSeq, session: session)
    }
}
