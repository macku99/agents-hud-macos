import Foundation
import HerdrKit
import HUDCore
import os

/// Files that could not be read, once each: `log stream --predicate 'subsystem == "app.itfrombit.agentshud"'`.
private let desktopLog = Logger(subsystem: "app.itfrombit.agentshud", category: "desktop")

/// One Claude Desktop instance: its name in the HUD and the Claude config directory its sessions use.
public struct DesktopInstance: Sendable {
    public let name: String
    public let configDirectory: URL

    public init(name: String, configDirectory: URL) {
        self.name = name
        self.configDirectory = configDirectory
    }
}

/// The Claude Code sessions one Claude Desktop instance runs. Every Claude Code process writes
/// `<config>/sessions/<pid>.json` with its status; Desktop's say so in `entrypoint`. The folder is
/// read every second, and a roster goes out only when something changed.
@MainActor
public final class DesktopAgentSource: AgentSource {
    public nonisolated let id: SourceID
    public let label: String

    private let instance: DesktopInstance
    private let processes: any ProcessTable
    private let pollSleep: @Sendable (Duration) async -> Void

    private var agents: [AgentSnapshot] = []
    /// The pid of each listed session, by session id.
    private var pids: [String: Int32] = [:]
    /// The `statusUpdatedAt` at which each idle session became idle. Kept while it stays idle, so a
    /// status written again without a new turn is not a new finish.
    private var idleSince: [String: UInt64] = [:]
    private var transcripts: [String: AgentSessionRef] = [:]
    /// Each file's last good read, by file name, standing in while the file is caught mid-write.
    private var lastReadable: [String: SessionFile] = [:]
    private var reportedUnreadable: Set<String> = []
    private var revision: UInt64 = 0
    private var continuation: AsyncStream<SourceSnapshot>.Continuation?
    private var pollTask: Task<Void, Never>?
    private var generation = 0

    public init(instance: DesktopInstance, processes: any ProcessTable = LiveProcessTable(),
                pollSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        id = SourceID("desktop:" + instance.name.lowercased().split(separator: " ").joined(separator: "-"))
        label = "\(instance.name) Desktop"
        self.instance = instance
        self.processes = processes
        self.pollSleep = pollSleep
    }

    public func snapshots() -> AsyncStream<SourceSnapshot> {
        stop()
        let generation = self.generation
        let (stream, continuation) = AsyncStream<SourceSnapshot>.makeStream()
        self.continuation = continuation
        agents = read()
        publish()
        pollTask = Task { [weak self] in await self?.poll(issuedIn: generation) }
        return stream
    }

    public func stop() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        continuation?.finish()
        continuation = nil
    }

    public func refresh() async -> SourceSnapshot? {
        agents = read()
        return publish()
    }

    /// The Desktop app process hosting the session: the session's topmost ancestor below launchd
    /// (`claude` → `disclaimer` → `Claude`). `nil` when the session is not listed or its process is gone.
    public func applicationPID(for key: AgentKey) -> Int32? {
        guard key.source == id, var pid = pids[key.id] else { return nil }
        while let parent = processes.parent(of: pid) {
            if parent <= 1 { return pid }
            pid = parent
        }
        return nil
    }

    private func poll(issuedIn generation: Int) async {
        while !Task.isCancelled, generation == self.generation {
            await pollSleep(.seconds(1))
            guard !Task.isCancelled, generation == self.generation else { return }
            let latest = read()
            if latest != agents {
                agents = latest
                publish()
            }
        }
    }

    @discardableResult
    private func publish() -> SourceSnapshot {
        revision += 1
        let snapshot = SourceSnapshot(revision: revision, state: .connected, agents: agents, isFullListing: true)
        continuation?.yield(snapshot)
        return snapshot
    }

    // MARK: Reading

    /// Every live Desktop session, oldest first. A missing folder means no sessions.
    private func read() -> [AgentSnapshot] {
        let folder = instance.configDirectory.appending(path: "sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // A sibling `<pid>.<hash>.key` holds the session's socket token; only `<pid>.json` is read.
        let files = names.filter { $0.hasSuffix(".json") }
        lastReadable = lastReadable.filter { files.contains($0.key) }
        let sessions = files.compactMap { name in
            session(in: folder.appending(path: name))
        }
        .filter { $0.entrypoint == "claude-desktop" && isLive($0) }
        .sorted { ($0.startedAt ?? 0, $0.sessionId) < ($1.startedAt ?? 0, $1.sessionId) }

        pids = Dictionary(sessions.map { ($0.sessionId, $0.pid) }, uniquingKeysWith: { first, _ in first })
        let listed = Set(pids.keys)
        idleSince = idleSince.filter { listed.contains($0.key) }
        transcripts = transcripts.filter { listed.contains($0.key) }
        return sessions.map(snapshot(of:))
    }

    /// Claude Code's format, not the HUD's, and it changes between versions: a file that does not
    /// decode is skipped, never fails the roster. One that decoded before is taken as it was then,
    /// since it may only be caught mid-write.
    private func session(in file: URL) -> SessionFile? {
        let name = file.lastPathComponent
        do {
            let session = try JSONDecoder().decode(SessionFile.self, from: Data(contentsOf: file))
            lastReadable[name] = session
            return session
        } catch {
            if lastReadable[name] == nil, reportedUnreadable.insert(name).inserted {
                desktopLog.notice("skipped unreadable session file \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return lastReadable[name]
        }
    }

    /// A file outlives a crashed process, and its pid can be reused, so the process must run and
    /// have started when the file says.
    private func isLive(_ session: SessionFile) -> Bool {
        guard let recorded = session.procStart, let started = processes.startTime(of: session.pid) else { return false }
        return Self.collapsingSpaces(recorded) == Self.collapsingSpaces(started)
    }

    private static func collapsingSpaces(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ")
    }

    private func snapshot(of session: SessionFile) -> AgentSnapshot {
        let status = Self.status(session.status)
        let updatedAt = session.statusUpdatedAt ?? 0
        if status == .done {
            if idleSince[session.sessionId] == nil { idleSince[session.sessionId] = updatedAt }
        } else {
            idleSince[session.sessionId] = nil
        }
        return AgentSnapshot(
            key: AgentKey(source: id, id: session.sessionId),
            incarnation: AgentIncarnation(ProcessIdentity(pid: session.pid, start: session.procStart)),
            title: session.name ?? session.cwd.map { ($0 as NSString).lastPathComponent } ?? session.sessionId,
            status: status,
            place: instance.name,
            kind: "claude",
            cwd: session.cwd,
            transcript: transcript(for: session.sessionId),
            completion: CompletionToken(counter: "idleSince", sequence: idleSince[session.sessionId] ?? 0),
            herdr: nil)
    }

    /// `waiting` is a permission prompt or a question for the user. Desktop shows no "seen" state,
    /// so every idle session counts as done until the HUD has shown it.
    private static func status(_ status: String?) -> AgentStatus {
        switch status {
        case "busy": .working
        case "waiting": .blocked
        case "idle": .done
        default: .unknown
        }
    }

    /// The session's transcript, searched for in this instance's own `projects` folders only, and
    /// searched for again while it has not been written yet.
    private func transcript(for session: String) -> AgentSessionRef? {
        if let known = transcripts[session] { return known }
        let projects = instance.configDirectory.appending(path: "projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        let found = folders.lazy
            .map { projects.appending(path: $0).appending(path: "\(session).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let found else { return nil }
        let ref = AgentSessionRef(kind: .path, value: found.path)
        transcripts[session] = ref
        return ref
    }
}

private struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let start: String?
}

/// The fields of `<pid>.json` the HUD uses.
private struct SessionFile: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String?
    let name: String?
    let status: String?
    let statusUpdatedAt: UInt64?
    let startedAt: UInt64?
    let procStart: String?
    let entrypoint: String?
}
