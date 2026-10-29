import HerdrKit
@testable import HUDCore

/// A source whose rosters the test publishes by hand. Its first roster goes out as soon as it starts.
/// A refresh answers with its current agents as a full listing, unless `answersRefresh` is off, and
/// only through its return value, so the store must apply that answer itself.
@MainActor
final class FakeAgentSource: AgentSource {
    nonisolated let id: SourceID
    let label: String
    private(set) var agents: [AgentSnapshot]
    private(set) var refreshCount = 0
    var answersRefresh = true
    /// Between `snapshots()` and `stop()`.
    private(set) var isRunning = false
    private var revision: UInt64 = 0
    private var continuation: AsyncStream<SourceSnapshot>.Continuation?

    init(_ name: String, agents: [AgentSnapshot] = []) {
        id = SourceID(name)
        label = name
        self.agents = agents
    }

    func snapshots() -> AsyncStream<SourceSnapshot> {
        stop()
        let (stream, continuation) = AsyncStream<SourceSnapshot>.makeStream()
        self.continuation = continuation
        isRunning = true
        publish(agents)
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        isRunning = false
    }

    func refresh() async -> SourceSnapshot? {
        refreshCount += 1
        guard answersRefresh else { return nil }
        revision += 1
        return SourceSnapshot(revision: revision, state: .connected, agents: agents, isFullListing: true)
    }

    /// Changes the agents the next refresh reports, without publishing them.
    func setAgents(_ agents: [AgentSnapshot]) {
        self.agents = agents
    }

    /// Publishes a roster. `revision` overrides the next revision, to deliver an older one late.
    @discardableResult
    func publish(_ agents: [AgentSnapshot], state: SourceState = .connected, isFullListing: Bool = true,
                 revision: UInt64? = nil) -> SourceSnapshot {
        if state == .connected { self.agents = agents }
        let number = revision ?? self.revision + 1
        self.revision = max(self.revision, number)
        let snapshot = SourceSnapshot(revision: number, state: state, agents: agents, isFullListing: isFullListing)
        continuation?.yield(snapshot)
        return snapshot
    }

    /// An agent of this source; `finished` names its latest finished turn.
    func agent(_ id: String, _ status: AgentStatus = .idle, finished: UInt64 = 1) -> AgentSnapshot {
        AgentSnapshot(key: AgentKey(source: self.id, id: id), incarnation: AgentIncarnation(id), title: id,
                      status: status, place: label, kind: "claude", cwd: nil, transcript: nil,
                      completion: CompletionToken(counter: "turn", sequence: finished), herdr: nil)
    }
}
