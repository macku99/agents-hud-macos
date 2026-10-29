import Foundation
import Synchronization
import Testing
import HerdrKit
import HUDCore
@testable import DesktopSessions

@Suite @MainActor struct DesktopAgentSourceTests {
    private let fixture = DesktopFixture()

    @Test func aDesktopSessionBecomesAnAgent() async throws {
        fixture.writeSession(pid: 12369, session: "7c1e4b2a", name: "Release notes", status: "idle",
                             cwd: "/Users/m/Work/app")

        let snapshot = try #require(await fixture.source().refresh())

        #expect(snapshot.state == .connected)
        #expect(snapshot.isFullListing)
        let agent = try #require(snapshot.agents.first)
        #expect(snapshot.agents.count == 1)
        #expect(agent.key == AgentKey(source: SourceID("desktop:personal"), id: "7c1e4b2a"))
        #expect(agent.title == "Release notes")
        #expect(agent.place == "Personal")
        #expect(agent.kind == "claude")
        #expect(agent.cwd == "/Users/m/Work/app")
        #expect(agent.status == .done)
        #expect(agent.herdr == nil)
    }

    @Test func aRealSessionFileDecodes() async throws {
        fixture.writeFile("12369.json", contents: DesktopFixture.realSessionFile)
        fixture.processes.set(pid: 12369, start: "Tue Oct 27 16:58:32 2026")

        let agent = try #require(await fixture.source().refresh()?.agents.first)

        #expect(agent.key.id == "7c1e4b2a-93d5-4f60-8a1b-2e6d0c9f5a37")
        #expect(agent.title == "Release notes draft")
        #expect(agent.cwd == "/Users/me/Work/example-app")
        #expect(agent.status == .done)
    }

    @Test(arguments: [("busy", AgentStatus.working), ("waiting", .blocked), ("idle", .done), ("dreaming", .unknown)])
    func statusesMapToTheHUDs(status: String, expected: AgentStatus) async throws {
        fixture.writeSession(pid: 1, session: "s1", status: status)

        let agent = try #require(await fixture.source().refresh()?.agents.first)

        #expect(agent.status == expected)
    }

    @Test func aSessionWithoutANameIsTitledByItsFolder() async throws {
        fixture.writeSession(pid: 1, session: "s1", name: nil, status: "idle", cwd: "/Users/m/Work/herdr-hud")

        let agent = try #require(await fixture.source().refresh()?.agents.first)

        #expect(agent.title == "herdr-hud")
    }

    @Test func sessionsStartedOutsideDesktopAreLeftOut() async {
        fixture.writeSession(pid: 1, session: "desktop", status: "idle")
        fixture.writeSession(pid: 2, session: "terminal", status: "idle", entrypoint: "cli")

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.map(\.key.id) == ["desktop"])
    }

    @Test func aSessionWhoseProcessIsGoneIsLeftOut() async {
        fixture.writeSession(pid: 1, session: "alive", status: "idle")
        fixture.writeSession(pid: 2, session: "gone", status: "idle")
        fixture.processes.remove(pid: 2)

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.map(\.key.id) == ["alive"])
    }

    @Test func aPidReusedByAnotherProcessDoesNotReviveTheSession() async {
        fixture.writeSession(pid: 1, session: "s1", status: "idle", procStart: "Tue Oct 27 16:58:32 2026")
        fixture.processes.set(pid: 1, start: "Wed Oct 28 09:00:00 2026")

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.isEmpty)
    }

    @Test func startTimesMatchWhateverTheirSpacing() async {
        fixture.writeSession(pid: 1, session: "s1", status: "idle", procStart: "Tue Oct 7 06:58:32 2026")
        fixture.processes.set(pid: 1, start: "Tue Oct  7 06:58:32 2026")

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.count == 1)
    }

    @Test func anUnreadableFileIsSkippedAndTheRestKept() async {
        fixture.writeFile("7.json", contents: "{ not json")
        fixture.writeFile("8.json", contents: #"{"pid": "eight"}"#)
        fixture.writeSession(pid: 9, session: "s9", status: "busy")

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.map(\.key.id) == ["s9"])
    }

    @Test func onlySessionFilesAreRead() async {
        fixture.writeSession(pid: 1, session: "s1", status: "idle")
        fixture.writeFile("1.abc123.key", contents: #"{"pid": 1, "sessionId": "from-key-file", "entrypoint": "claude-desktop"}"#)

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.map(\.key.id) == ["s1"])
    }

    @Test func sessionsAreListedOldestFirst() async {
        fixture.writeSession(pid: 1, session: "newer", status: "idle", startedAt: 2_000)
        fixture.writeSession(pid: 2, session: "older", status: "idle", startedAt: 1_000)

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.map(\.key.id) == ["older", "newer"])
    }

    @Test func aMissingSessionsFolderMeansNoAgents() async throws {
        let source = DesktopAgentSource(instance: DesktopInstance(name: "Client Work", configDirectory: fixture.root.appending(path: "absent")),
                                        processes: fixture.processes)

        let snapshot = try #require(await source.refresh())

        #expect(snapshot.state == .connected)
        #expect(snapshot.agents.isEmpty)
        #expect(source.id == SourceID("desktop:client-work"))
    }

    @Test func aFinishedTurnKeepsItsMarkUntilTheSessionWorksAgain() async throws {
        let source = fixture.source()
        fixture.writeSession(pid: 1, session: "s1", status: "idle", statusUpdatedAt: 100)
        let first = try #require(await source.refresh()?.agents.first?.completion)

        fixture.writeSession(pid: 1, session: "s1", status: "idle", statusUpdatedAt: 200)
        let rewritten = try #require(await source.refresh()?.agents.first?.completion)

        fixture.writeSession(pid: 1, session: "s1", status: "busy", statusUpdatedAt: 300)
        _ = await source.refresh()
        fixture.writeSession(pid: 1, session: "s1", status: "idle", statusUpdatedAt: 400)
        let next = try #require(await source.refresh()?.agents.first?.completion)

        #expect(rewritten == first)
        #expect(next != first)
    }

    @Test func aFileCaughtMidWriteKeepsTheSessionAndItsFinish() async throws {
        let source = fixture.source()
        fixture.writeSession(pid: 1, session: "s1", status: "idle", statusUpdatedAt: 100)
        let first = try #require(await source.refresh()?.agents.first?.completion)

        fixture.writeFile("1.json", contents: #"{"pid": 1, "sessionId": "s1", "#)
        let midWrite = await source.refresh()?.agents ?? []
        fixture.writeSession(pid: 1, session: "s1", status: "idle", statusUpdatedAt: 200)
        let after = try #require(await source.refresh()?.agents.first?.completion)

        #expect(midWrite.map(\.key.id) == ["s1"])
        #expect(midWrite.first?.completion == first)
        #expect(after == first)
    }

    @Test func theTranscriptIsFoundInTheInstancesOwnProjects() async throws {
        fixture.writeSession(pid: 1, session: "with-transcript", status: "idle")
        fixture.writeSession(pid: 2, session: "without", status: "idle")
        let transcript = fixture.writeTranscript(project: "-Users-m-Work-app", session: "with-transcript")

        let agents = await fixture.source().refresh()?.agents ?? []

        #expect(agents.first { $0.key.id == "with-transcript" }?.transcript == AgentSessionRef(kind: .path, value: transcript.path))
        #expect(agents.first { $0.key.id == "without" }?.transcript == nil)
    }

    @Test func aTranscriptWrittenLaterIsPickedUp() async throws {
        let source = fixture.source()
        fixture.writeSession(pid: 1, session: "s1", status: "busy")
        #expect(await source.refresh()?.agents.first?.transcript == nil)

        fixture.writeTranscript(project: "-Users-m-Work-app", session: "s1")

        #expect(await source.refresh()?.agents.first?.transcript != nil)
    }

    @Test func theFirstRosterArrivesOnTheStreamAndPollsPublishOnlyChanges() async throws {
        fixture.writeSession(pid: 1, session: "s1", status: "busy")
        let polls = PollGate()
        let source = fixture.source(pollSleep: polls.sleep)
        var snapshots = source.snapshots().makeAsyncIterator()
        defer { source.stop() }

        let first = try #require(await snapshots.next())
        #expect(first.agents.map(\.status) == [.working])

        await polls.tick()
        fixture.writeSession(pid: 1, session: "s1", status: "idle")
        await polls.tick()

        let changed = try #require(await snapshots.next())
        #expect(changed.agents.map(\.status) == [.done])
        #expect(changed.revision == first.revision + 1)
    }

    @Test func restartingEndsTheEarlierStreamAndStopEndsTheLatest() async throws {
        fixture.writeSession(pid: 1, session: "s1", status: "busy")
        let polls = PollGate()
        let source = fixture.source(pollSleep: polls.sleep)
        var earlier = source.snapshots().makeAsyncIterator()
        _ = await earlier.next()

        var latest = source.snapshots().makeAsyncIterator()
        #expect(await earlier.next() == nil)
        let first = try #require(await latest.next())
        await polls.tick()
        fixture.writeSession(pid: 1, session: "s1", status: "idle")
        await polls.tick()
        let changed = try #require(await latest.next())
        source.stop()

        #expect(changed.revision == first.revision + 1)
        #expect(await latest.next() == nil)
    }

    @Test func theHostApplicationIsTheSessionsTopmostAncestor() async throws {
        fixture.writeSession(pid: 34405, session: "s1", status: "idle")
        fixture.processes.set(pid: 34405, start: DesktopFixture.start, parent: 34404)
        fixture.processes.set(pid: 34404, start: DesktopFixture.start, parent: 9209)
        fixture.processes.set(pid: 9209, start: DesktopFixture.start, parent: 1)
        let source = fixture.source()
        let key = try #require(await source.refresh()?.agents.first?.key)

        #expect(source.applicationPID(for: key) == 9209)
        #expect(source.applicationPID(for: AgentKey(source: source.id, id: "unknown")) == nil)
    }
}

/// A config directory in a temporary folder, with session files written by the test, and a process
/// table where every pid the test writes is alive with the start its file records.
@MainActor
final class DesktopFixture {
    static let start = "Tue Oct 27 16:58:32 2026"
    let root = FileManager.default.temporaryDirectory.appending(path: "desktop-\(UUID().uuidString)")
    let processes = FakeProcessTable()

    var config: URL { root.appending(path: "config") }

    func source(pollSleep: @escaping @Sendable (Duration) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) }) -> DesktopAgentSource {
        DesktopAgentSource(instance: DesktopInstance(name: "Personal", configDirectory: config), processes: processes,
                           pollSleep: pollSleep)
    }

    func writeSession(pid: Int32, session: String, name: String? = "session", status: String, cwd: String = "/Users/m/Work/app",
                      entrypoint: String = "claude-desktop", procStart: String = DesktopFixture.start,
                      startedAt: UInt64 = 1_000, statusUpdatedAt: UInt64 = 1_000) {
        var fields: [String: Any] = [
            "pid": pid, "sessionId": session, "cwd": cwd, "startedAt": startedAt, "procStart": procStart,
            "kind": "interactive", "entrypoint": entrypoint, "hostSessionId": "local_\(session)", "status": status,
            "statusUpdatedAt": statusUpdatedAt, "updatedAt": statusUpdatedAt,
        ]
        if let name { fields["name"] = name }
        let data = try! JSONSerialization.data(withJSONObject: fields)
        writeFile("\(pid).json", contents: String(decoding: data, as: UTF8.self))
        if processes.startTime(of: pid) == nil { processes.set(pid: pid, start: procStart) }
    }

    func writeFile(_ name: String, contents: String) {
        let sessions = config.appending(path: "sessions")
        try! FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try! Data(contents.utf8).write(to: sessions.appending(path: name))
    }

    @discardableResult
    func writeTranscript(project: String, session: String) -> URL {
        let folder = config.appending(path: "projects").appending(path: project)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(session).jsonl")
        try! Data().write(to: url)
        return url
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A Desktop session file as Claude Code 2.1.308 wrote it, with its socket path and bridge id removed.
    static let realSessionFile = #"""
    {"pid": 12369, "sessionId": "7c1e4b2a-93d5-4f60-8a1b-2e6d0c9f5a37", "cwd": "/Users/me/Work/example-app", "startedAt": 1793120312948, "procStart": "Tue Oct 27 16:58:32 2026", "version": "2.1.308", "peerProtocol": 1, "peerFeatures": ["notify_idle", "reply_across_default_dirs", "artifact_yield"], "kind": "interactive", "entrypoint": "claude-desktop", "hostSessionId": "local_3b8f1d6e-0a42-4c7d-b951-6e2a8f0c4d19", "pidDomain": "darwin", "name": "Release notes draft", "nameSource": "user", "nameSince": 1793120316407, "status": "idle", "updatedAt": 1793121083054, "statusUpdatedAt": 1793121083054}
    """#
}

final class FakeProcessTable: ProcessTable {
    private let processes = Mutex<[Int32: (start: String, parent: Int32)]>([:])

    func set(pid: Int32, start: String, parent: Int32 = 1) {
        processes.withLock { $0[pid] = (start, parent) }
    }

    func remove(pid: Int32) {
        processes.withLock { _ = $0.removeValue(forKey: pid) }
    }

    func startTime(of pid: Int32) -> String? {
        processes.withLock { $0[pid]?.start }
    }

    func parent(of pid: Int32) -> Int32? {
        processes.withLock { $0[pid]?.parent }
    }
}

/// A poll wait that lasts until the test calls `tick()`, which returns once the poll after it has run.
final class PollGate: Sendable {
    private let state = Mutex<(ticks: Int, waits: Int)>((0, 0))

    var sleep: @Sendable (Duration) async -> Void {
        { [self] _ in
            state.withLock { $0.waits += 1 }
            while !Task.isCancelled {
                let ticked = state.withLock { state in
                    guard state.ticks > 0 else { return false }
                    state.ticks -= 1
                    return true
                }
                if ticked { return }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    /// Ends the current wait and returns once the source has polled and started waiting again.
    func tick() async {
        let waits = state.withLock { state in
            state.ticks += 1
            return state.waits
        }
        while state.withLock({ $0.waits }) <= waits {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
