import Foundation
import HerdrKit
import Observation
import os

/// Send attempts and their outcomes, never the prompt text: `log stream --predicate 'subsystem == "app.itfrombit.agentshud"'`.
private let sendLog = Logger(subsystem: "app.itfrombit.agentshud", category: "send")

/// The HUD's single source of truth. Windows observe its state and call its intents; nothing else
/// talks to the agent sources.
@MainActor
@Observable
public final class HUDStore {
    /// Sorted: attention first, then working, then idle.
    public private(set) var roster: [RosterEntry] = []
    public private(set) var selectedAgent: AgentKey?
    public private(set) var isPanelOpen = false
    public private(set) var isHUDVisible = true
    public private(set) var alerts: [HUDAlert] = []
    /// Blocked agents plus unseen finished ones.
    public private(set) var badgeCount = 0
    public private(set) var isAnyAgentWorking = false
    /// How each source stands, in the order the sources were given.
    public private(set) var connections: [SourceConnection]

    @ObservationIgnored private let sources: [any AgentSource]
    private let now: @Sendable () -> Date

    /// Every source's latest agents, merged in source order.
    private var agents: [AgentSnapshot] = []
    private var agentsBySource: [SourceID: [AgentSnapshot]] = [:]
    private var appliedRevisions: [SourceID: UInt64] = [:]
    private var stateSince: [AgentKey: Date] = [:]
    /// The last finished turn viewed per agent. Keyed by incarnation so a new agent under the same key starts unseen.
    private var viewedCompletions: [AgentInstance: CompletionToken] = [:]
    /// Sources whose changes raise no alerts until their next full roster, which may hold changes
    /// that are old news: every source from start or unhide.
    private var holdingAlerts: Set<SourceID> = []
    private var drafts: [AgentKey: String] = [:]
    private var sendStates: [AgentKey: SendState] = [:]
    /// The latest send; each send waits for the one before it, so only one is ever in flight.
    @ObservationIgnored private var lastSend: Task<PromptOutcome, Never>?
    @ObservationIgnored private var feeds: [Task<Void, Never>] = []
    @ObservationIgnored private var unhideReloadTask: Task<Void, Never>?
    /// Bumped by `stop()`, so answers to requests made before it are dropped and a `start()` still
    /// loading knows it was stopped or replaced.
    @ObservationIgnored private var generation = 0

    public init(sources: [any AgentSource], now: @escaping @Sendable () -> Date = Date.init) {
        self.sources = sources
        self.now = now
        connections = sources.map { SourceConnection(id: $0.id, label: $0.label, state: .connecting) }
    }

    /// Starts every source and returns once each has published its first roster; their later rosters
    /// are followed in tasks the store owns until `stop()`.
    public func start() async {
        stop()
        let generation = self.generation
        connections = sources.map { SourceConnection(id: $0.id, label: $0.label, state: .connecting) }
        holdingAlerts = Set(sources.map(\.id))
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { [weak self] in await self?.follow(source, issuedIn: generation) }
            }
        }
    }

    public func stop() {
        generation += 1
        feeds.forEach { $0.cancel() }
        feeds = []
        sources.forEach { $0.stop() }
        unhideReloadTask?.cancel()
        unhideReloadTask = nil
    }

    /// Reads every source's roster again and returns once each answer is applied.
    public func refresh() async {
        await refreshSources(issuedIn: generation)
    }

    /// Selects an agent in the panel and counts as viewing it.
    public func select(_ key: AgentKey) {
        selectedAgent = key
        clearRefusal(for: key)
        guard isPanelOpen else { return }
        markSelectedAgentViewed()
        rebuildRoster()
    }

    public func togglePanel() {
        if isPanelOpen {
            isPanelOpen = false
        } else {
            openPanel()
        }
    }

    public func openPanel() {
        // The panel is anchored to H, so it cannot be open while H is hidden.
        if !isHUDVisible { showHUD() }
        isPanelOpen = true
        alerts = []
        if selectedAgent == nil { selectedAgent = roster.first?.id }
        markSelectedAgentViewed()
        rebuildRoster()
    }

    /// Opens the panel with `key` selected, as clicking an alert does.
    public func openPanel(on key: AgentKey) {
        select(key)
        openPanel()
    }

    public func toggleHUD() {
        if isHUDVisible {
            isHUDVisible = false
            isPanelOpen = false
            alerts = []
        } else {
            showHUD()
        }
    }

    public func draft(for key: AgentKey) -> String { drafts[key, default: ""] }

    public func setDraft(_ text: String, for key: AgentKey) {
        drafts[key] = text
        clearRefusal(for: key)
    }

    public func sendState(for key: AgentKey) -> SendState { sendStates[key, default: .ready] }

    public func send(for key: AgentKey) async {
        guard let agent = agents.first(where: { $0.key == key }) else {
            sendLog.notice("send to \(key.id, privacy: .public) skipped: agent not in the roster")
            return
        }
        guard let handle = agent.herdr, let source = herdrSource(for: key) else {
            sendLog.notice("send to \(key.id, privacy: .public) skipped: agent takes no prompts from the HUD")
            return
        }
        guard [.idle, .done].contains(agent.status) else {
            sendLog.notice("send to \(key.id, privacy: .public) skipped: agent is \(agent.status.rawValue, privacy: .public)")
            return
        }
        switch sendState(for: key) {
        case .ready, .refused: break
        case .sending, .uncertain:
            sendLog.notice("send to \(key.id, privacy: .public) skipped: a send is \(self.sendState(for: key).name, privacy: .public)")
            return
        }
        let text = draft(for: key)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendLog.notice("send to \(key.id, privacy: .public) skipped: empty draft")
            return
        }
        sendLog.notice("send to \(key.id, privacy: .public) started, \(text.utf8.count, privacy: .public) bytes")

        sendStates[key] = .sending
        let identity = handle.identity
        let previous = lastSend
        let send = Task {
            _ = await previous?.value
            return await source.send(text, to: identity)
        }
        lastSend = send

        let outcome = await send.value
        sendLog.notice("send to \(key.id, privacy: .public) ended: \(outcome.name, privacy: .public) \(String(describing: outcome), privacy: .private)")
        switch outcome {
        case .delivered:
            sendStates[key] = .ready
            if draft(for: key) == text { drafts[key] = "" }
        case .refused(let reason):
            sendStates[key] = .refused(reason)
        case .uncertain(let detail):
            sendStates[key] = .uncertain(detail)
        }
    }

    /// The user checked herdr after an uncertain send; sending is allowed again.
    public func reconcile(_ key: AgentKey) {
        if case .uncertain = sendState(for: key) { sendStates[key] = .ready }
    }

    /// Focuses a herdr agent's pane in herdr; a failed focus reloads that source.
    public func focus(_ key: AgentKey) async {
        guard let source = herdrSource(for: key) else { return }
        let generation = self.generation
        do {
            try await source.focus(PaneID(key.id))
        } catch {
            guard generation == self.generation else { return }
            await refresh(source, issuedIn: generation)
        }
    }

    /// A herdr agent's recent screen text (see `HerdrAgentSource.screenText`). `nil` when the agent
    /// is not in herdr or herdr cannot be read.
    public func screenText(for key: AgentKey, source: ReadSource) async -> String? {
        await herdrSource(for: key)?.screenText(for: PaneID(key.id), source: source)
    }

    public func dismissAlert(_ id: HUDAlert.ID) {
        alerts.removeAll { $0.id == id }
    }

    private func showHUD() {
        isHUDVisible = true
        holdingAlerts = Set(sources.map(\.id))
        // Read now: the task may not run until after a stop(), and must then count as stopped.
        let generation = self.generation
        unhideReloadTask?.cancel()
        unhideReloadTask = Task { [weak self] in await self?.refreshSources(issuedIn: generation) }
    }

    private func herdrSource(for key: AgentKey) -> HerdrAgentSource? {
        sources.first { $0.id == key.source } as? HerdrAgentSource
    }

    private func clearRefusal(for key: AgentKey) {
        if case .refused = sendState(for: key) { sendStates[key] = .ready }
    }

    // MARK: Sources

    /// Applies the source's rosters until it stops, returning once the first is applied (or the
    /// source ended without one).
    private func follow(_ source: any AgentSource, issuedIn generation: Int) async {
        // A stop() or another start() can land before this task first runs; starting the source then
        // would leave it running for nobody, or end the newer start's stream.
        guard generation == self.generation else { return }
        let snapshots = source.snapshots()
        await withCheckedContinuation { (loaded: CheckedContinuation<Void, Never>) in
            feeds.append(Task { [weak self] in
                var waitingForFirst = true
                for await snapshot in snapshots {
                    guard let self, generation == self.generation else { break }
                    apply(snapshot, from: source.id)
                    if waitingForFirst {
                        waitingForFirst = false
                        loaded.resume()
                    }
                }
                if waitingForFirst { loaded.resume() }
            })
        }
    }

    private func refreshSources(issuedIn generation: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { [weak self] in await self?.refresh(source, issuedIn: generation) }
            }
        }
    }

    /// `generation` is the one the refresh was asked for in, so an answer after `stop()` is dropped.
    private func refresh(_ source: any AgentSource, issuedIn generation: Int) async {
        guard let snapshot = await source.refresh(), generation == self.generation else { return }
        apply(snapshot, from: source.id)
    }

    /// A refresh's answer is applied directly and also arrives on the source's stream; whichever
    /// comes second, or any older snapshot arriving late, is dropped by its revision.
    private func apply(_ snapshot: SourceSnapshot, from source: SourceID) {
        guard snapshot.revision > appliedRevisions[source, default: 0] else { return }
        appliedRevisions[source] = snapshot.revision
        if let index = connections.firstIndex(where: { $0.id == source }) {
            connections[index].state = snapshot.state
        }
        if agentsBySource[source] != snapshot.agents {
            agentsBySource[source] = snapshot.agents
            update(to: sources.flatMap { agentsBySource[$0.id] ?? [] })
        }
        if snapshot.isFullListing, snapshot.state == .connected { holdingAlerts.remove(source) }
    }

    // MARK: Roster

    private func update(to snapshot: [AgentSnapshot]) {
        // A key reused by another agent counts as a new agent: no prior state, no transition.
        let previous = Dictionary(agents.map { ($0.instance, $0) }, uniquingKeysWith: { first, _ in first })
        let at = now()
        stateSince = Dictionary(snapshot.map { agent in
            let since = previous[agent.instance]?.status == agent.status ? stateSince[agent.key] : nil
            return (agent.key, since ?? at)
        }, uniquingKeysWith: { first, _ in first })
        let instanceByKey = Dictionary(agents.map { ($0.key, $0.instance) }, uniquingKeysWith: { first, _ in first })
        let reusedKeys = Set(snapshot.filter { agent in
            instanceByKey[agent.key].map { $0 != agent.instance } ?? false
        }.map(\.key))
        // Their alerts name the agent that left.
        alerts.removeAll { reusedKeys.contains($0.key) }
        for agent in snapshot where raisesAlerts(for: agent.key.source) {
            guard let alert = previous[agent.instance].flatMap({ alert(for: agent, after: $0, at: at) }) else { continue }
            alerts.removeAll { $0.key == alert.key && $0.kind == alert.kind }
            alerts.append(alert)
        }
        let blocked = Set(snapshot.filter { $0.status == .blocked }.map(\.key))
        alerts.removeAll { $0.kind == .needsInput && !blocked.contains($0.key) }
        agents = snapshot
        if isPanelOpen { markSelectedAgentViewed() }
        rebuildRoster()
    }

    private func markSelectedAgentViewed() {
        if let selected = agents.first(where: { $0.key == selectedAgent }) {
            viewedCompletions[selected.instance] = selected.completion
        }
    }

    private func raisesAlerts(for source: SourceID) -> Bool {
        isHUDVisible && !isPanelOpen && !holdingAlerts.contains(source)
    }

    /// Only an agent the store already knew can be newly blocked or newly finished.
    private func alert(for agent: AgentSnapshot, after previous: AgentSnapshot, at: Date) -> HUDAlert? {
        let kind: HUDAlert.Kind
        if agent.status == .blocked, previous.status != .blocked {
            kind = .needsInput
        } else if agent.status == .done, previous.status != .done || agent.completion != previous.completion {
            kind = .finished
        } else {
            return nil
        }
        return HUDAlert(key: agent.key, kind: kind, title: agent.title, preview: "", at: at)
    }

    private func rebuildRoster() {
        let entries = agents.map { RosterEntry(agent: $0, attention: attention(of: $0), stateSince: stateSince[$0.key]) }
        roster = RosterOrder.sorted(entries)
        badgeCount = entries.count { $0.attention != .none }
        isAnyAgentWorking = agents.contains { $0.status == .working }
    }

    private func attention(of agent: AgentSnapshot) -> Attention {
        switch agent.status {
        case .blocked: .blocked
        case .done where agent.completion.isNewer(than: viewedCompletions[agent.instance]): .unseen
        default: .none
        }
    }
}

/// One agent incarnation: the key plus which agent holds it.
private struct AgentInstance: Hashable {
    let key: AgentKey
    let incarnation: AgentIncarnation
}

private extension AgentSnapshot {
    var instance: AgentInstance { AgentInstance(key: key, incarnation: incarnation) }
}

private extension SendState {
    /// The state without its detail, which can carry herdr's own error text.
    var name: String {
        switch self {
        case .ready: "ready"
        case .sending: "sending"
        case .uncertain: "uncertain"
        case .refused: "refused"
        }
    }
}

private extension PromptOutcome {
    /// The outcome without its detail, which can carry herdr's own error text.
    var name: String {
        switch self {
        case .delivered: "delivered"
        case .refused: "refused"
        case .uncertain: "uncertain"
        }
    }
}
