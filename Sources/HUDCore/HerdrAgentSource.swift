import Foundation
import HerdrKit

/// The agents herdr runs on one machine. Follows herdr's events, reconnecting with backoff, and
/// reloads the whole roster every 30 seconds because herdr sends no event when a pane closes.
@MainActor
public final class HerdrAgentSource: AgentSource {
    public nonisolated let id: SourceID
    public let label = "herdr"

    private let client: any HerdrClient
    private let machine: MachineID
    private let now: @Sendable () -> Date
    /// Wait before a reconnect and between periodic reloads; tests replace them so no real time passes.
    private let reconnectSleep: @Sendable (Duration) async -> Void
    private let reloadSleep: @Sendable (Duration) async -> Void

    /// herdr's latest snapshot, in herdr's order.
    private var agents: [AgentInfo] = []
    private var state: SourceState = .connecting
    private var revision: UInt64 = 0
    private var continuation: AsyncStream<SourceSnapshot>.Continuation?
    /// Set once the run has subscribed to events. Until then nothing goes on the stream, so a refresh
    /// during the first load cannot become the first snapshot.
    private var isFollowing = false
    private var runTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    /// Bumped by `stop()`, so answers to requests made before it are dropped and a run still
    /// loading knows it was stopped or replaced.
    private var generation = 0

    public convenience init(client: any HerdrClient, machine: MachineID = .local, now: @escaping @Sendable () -> Date = Date.init) {
        let sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        self.init(client: client, machine: machine, now: now, reconnectSleep: sleep, reloadSleep: sleep)
    }

    init(client: any HerdrClient, machine: MachineID = .local, now: @escaping @Sendable () -> Date,
         reconnectSleep: @escaping @Sendable (Duration) async -> Void,
         reloadSleep: @escaping @Sendable (Duration) async -> Void) {
        self.id = Self.id(for: machine)
        self.client = client
        self.machine = machine
        self.now = now
        self.reconnectSleep = reconnectSleep
        self.reloadSleep = reloadSleep
    }

    public nonisolated static func id(for machine: MachineID) -> SourceID {
        switch machine {
        case .local: SourceID("herdr:local")
        }
    }

    public func snapshots() -> AsyncStream<SourceSnapshot> {
        stop()
        let generation = self.generation
        state = .connecting
        let (stream, continuation) = AsyncStream<SourceSnapshot>.makeStream()
        self.continuation = continuation
        runTask = Task { [weak self] in await self?.run(issuedIn: generation) }
        return stream
    }

    public func stop() {
        generation += 1
        isFollowing = false
        runTask?.cancel()
        runTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        continuation?.finish()
        continuation = nil
    }

    public func refresh() async -> SourceSnapshot? {
        let generation = self.generation
        guard await load(emptyingOnFailure: false, issuedIn: generation) else { return nil }
        return publish(isFullListing: state == .connected)
    }

    // MARK: herdr-only actions

    /// Focuses the agent's pane in herdr, which also marks it seen there.
    func focus(_ pane: PaneID) async throws(HerdrError) {
        try await client.focus(pane, on: machine)
    }

    func send(_ text: String, to identity: AgentIdentity) async -> PromptOutcome {
        await client.send(text, to: identity)
    }

    /// The pane's recent screen text: `.recentUnwrapped` for agents without a transcript, `.visible`
    /// for a blocked agent's question. While the agent is not idle herdr refuses `.recentUnwrapped`,
    /// so the visible screen comes back instead. `nil` when herdr cannot be read.
    func screenText(for pane: PaneID, source: ReadSource) async -> String? {
        let lines = switch source {
        case .recentUnwrapped: 180
        case .visible: 40
        }
        do {
            return try await client.read(pane, source: source, lines: lines, on: machine)
        } catch .rejected(code: "agent_not_idle", _) where source == .recentUnwrapped {
            // herdr 0.9.5 answers `agent_not_idle` to scrollback reads until the agent is idle (seen live).
            return await screenText(for: pane, source: .visible)
        } catch {
            return nil
        }
    }

    // MARK: Loading

    /// Loads the first roster, subscribes, and only then publishes it, so no event emitted after the
    /// first snapshot can be missed.
    private func run(issuedIn generation: Int) async {
        guard await load(emptyingOnFailure: true, issuedIn: generation) else { return }
        let events = client.events(on: machine)
        let subscribedAt = now()
        isFollowing = true
        publish(isFullListing: state == .connected)
        eventsTask = Task { [weak self] in await self?.follow(events, subscribedAt: subscribedAt, issuedIn: generation) }
        reloadTask = Task { [weak self] in await self?.reloadPeriodically(issuedIn: generation) }
    }

    /// Reads the whole roster without publishing it. A failed read keeps the last roster; only a start
    /// has no roster worth keeping. False when the answer arrived after `stop()` and was dropped.
    private func load(emptyingOnFailure: Bool, issuedIn generation: Int) async -> Bool {
        do {
            let listed = try await client.agents(on: machine)
            guard generation == self.generation else { return false }
            state = .connected
            agents = listed
        } catch {
            guard generation == self.generation else { return false }
            state = .unavailable(Self.unavailable(error))
            if emptyingOnFailure { agents = [] }
        }
        return true
    }

    private func reload(issuedIn generation: Int) async {
        guard await load(emptyingOnFailure: false, issuedIn: generation) else { return }
        publish(isFullListing: state == .connected)
    }

    @discardableResult
    private func publish(isFullListing: Bool) -> SourceSnapshot {
        revision += 1
        let snapshot = SourceSnapshot(revision: revision, state: state, agents: agents.map { Self.snapshot(of: $0, on: machine) },
                                      isFullListing: isFullListing)
        if isFollowing { continuation?.yield(snapshot) }
        return snapshot
    }

    /// How the HUD shows an agent herdr runs on `machine`.
    public nonisolated static func snapshot(of agent: AgentInfo, on machine: MachineID) -> AgentSnapshot {
        AgentSnapshot(
            key: AgentKey(source: id(for: machine), id: agent.paneID.rawValue),
            incarnation: AgentIncarnation(agent.identity),
            title: agent.title,
            status: agent.status,
            place: agent.workspaceID,
            kind: agent.agent,
            cwd: agent.cwd,
            transcript: agent.session,
            completion: completion(of: agent),
            herdr: HerdrHandle(identity: agent.identity, stateChangeSeq: agent.stateChangeSeq))
    }

    /// herdr's `completion_seq` names the finished turn; when herdr leaves that null, the
    /// `state_change_seq` of the agent's current state stands in.
    nonisolated static func completion(of agent: AgentInfo) -> CompletionToken {
        if let completion = agent.completionSeq {
            CompletionToken(counter: "completion", sequence: completion)
        } else {
            CompletionToken(counter: "stateChange", sequence: agent.stateChangeSeq)
        }
    }

    nonisolated static func unavailable(_ error: any Error) -> String {
        switch error as? HerdrError {
        case .notInstalled: "herdr is not installed"
        case .unreachable: "herdr is not reachable"
        case .timedOut: "herdr is not responding"
        case .outputTooLarge: "herdr sent more than the HUD reads"
        case .unexpectedResponse, nil: "herdr sent a reply the HUD does not understand"
        case .rejected: "herdr refused the request"
        }
    }

    // MARK: Events

    /// Follows herdr's events until cancelled. A subscription that ends or throws means changes may
    /// have been missed, so the roster is reloaded before subscribing again. The wait before that
    /// doubles with each subscription that ends without proving healthy, by delivering an event or
    /// staying open for 30 seconds; a reload succeeding proves nothing about the subscription.
    private func follow(_ initial: AsyncThrowingStream<HerdrEvent, any Error>, subscribedAt initialSubscription: Date,
                        issuedIn generation: Int) async {
        var events = initial
        var subscribedAt = initialSubscription
        var unhealthyDrops = 0
        while isRunning(generation) {
            var deliveredEvent = false
            do {
                // A stopped stream can still hold buffered events; they belong to the stopped run.
                for try await event in events {
                    guard isRunning(generation) else { return }
                    deliveredEvent = true
                    await handle(event, issuedIn: generation)
                }
            } catch {}
            guard isRunning(generation) else { return }
            if deliveredEvent || now().timeIntervalSince(subscribedAt) >= 30 { unhealthyDrops = 0 }
            await reconnectSleep(Self.reconnectDelay(after: unhealthyDrops))
            unhealthyDrops += 1
            guard isRunning(generation) else { return }
            await reload(issuedIn: generation)
            guard isRunning(generation) else { return }
            events = client.events(on: machine)
            subscribedAt = now()
        }
    }

    /// herdr sends no event when a pane closes, so only a full reload drops a closed agent.
    private func reloadPeriodically(issuedIn generation: Int) async {
        while isRunning(generation) {
            await reloadSleep(.seconds(30))
            guard isRunning(generation) else { return }
            await reload(issuedIn: generation)
        }
    }

    private func isRunning(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == self.generation
    }

    private static func reconnectDelay(after unhealthyDrops: Int) -> Duration {
        .seconds(min(30, 1 << min(unhealthyDrops, 5)))
    }

    private func handle(_ event: HerdrEvent, issuedIn generation: Int) async {
        switch event {
        case .agentStatusChanged(let pane, _):
            guard agents.contains(where: { $0.paneID == pane }) else {
                return await reload(issuedIn: generation)
            }
            do {
                let fetched = try await client.agent(pane, on: machine)
                guard generation == self.generation else { return }
                replace(with: fetched)
            } catch {
                guard generation == self.generation else { return }
                await reload(issuedIn: generation)
            }
        }
    }

    /// A fetch can return after a newer full listing; an older state of the same agent is dropped.
    private func replace(with agent: AgentInfo) {
        guard let index = agents.firstIndex(where: { $0.paneID == agent.paneID }) else { return }
        let current = agents[index]
        if current.identity == agent.identity, agent.stateChangeSeq < current.stateChangeSeq { return }
        agents[index] = agent
        publish(isFullListing: false)
    }
}
