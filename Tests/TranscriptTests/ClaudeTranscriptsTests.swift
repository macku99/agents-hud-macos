import Foundation
import HerdrKit
import Testing
@testable import Transcript

private typealias F = TranscriptFixture

@Suite struct TranscriptClaudeTranscriptsTests {
    private actor Recorder {
        private(set) var emissions: [[ChatBlock]] = []
        private(set) var finished = false
        func record(_ blocks: [ChatBlock]) { emissions.append(blocks) }
        func finish() { finished = true }
    }

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ClaudeTranscriptsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: root) }

    private func transcript(_ lines: [String], named name: String = "session.jsonl") throws -> URL {
        let url = root.appending(path: name)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
        return url
    }

    private func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
    }

    @discardableResult
    private func session(configDir: String, project: String, id: String, modified: Date) throws -> URL {
        let folder = root.appending(path: "\(configDir)/projects/\(project)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(id).jsonl")
        try Data(F.prompt("p-\(configDir)", "From \(configDir)").utf8 + Data("\n".utf8)).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func source(_ configDirs: [String] = []) -> ClaudeTranscripts {
        ClaudeTranscripts(configDirectories: configDirs.map { root.appending(path: $0) },
                          pollInterval: .milliseconds(20), tailBytes: 1 << 20)
    }

    private func record(_ stream: AsyncStream<[ChatBlock]>) -> (Recorder, Task<Void, Never>) {
        let recorder = Recorder()
        let consumer = Task {
            for await blocks in stream { await recorder.record(blocks) }
            await recorder.finish()
        }
        return (recorder, consumer)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    // MARK: Resolving the reference

    @Test func aPathReferenceIsUsedDirectly() {
        defer { cleanUp() }
        let url = source().transcriptURL(for: AgentSessionRef(kind: .path, value: "/somewhere/abc.jsonl"))
        #expect(url == URL(filePath: "/somewhere/abc.jsonl"))
    }

    @Test func anIDResolvesToTheNewestMatchAcrossConfigDirectories() throws {
        defer { cleanUp() }
        try session(configDir: ".claude-a", project: "-proj-one", id: "abc", modified: F.time(0))
        let newest = try session(configDir: ".claude-b", project: "-proj-two", id: "abc", modified: F.time(60))
        try session(configDir: ".claude-b", project: "-proj-three", id: "abc", modified: F.time(30))
        try session(configDir: ".claude-b", project: "-proj-two", id: "other", modified: F.time(90))

        let url = source([".claude-a", ".claude-b", ".claude-missing"]).transcriptURL(for: AgentSessionRef(kind: .id, value: "abc"))
        #expect(url?.standardizedFileURL == newest.standardizedFileURL)
    }

    @Test(arguments: ["unknown", "../-proj-one/abc", ""])
    func anIDWithoutAMatchingTranscriptDoesNotResolve(id: String) throws {
        defer { cleanUp() }
        try session(configDir: ".claude-a", project: "-proj-one", id: "abc", modified: F.time(0))
        #expect(source([".claude-a"]).transcriptURL(for: AgentSessionRef(kind: .id, value: id)) == nil)
    }

    // MARK: The stream

    @Test func theStreamEmitsTheLastBlocksUpToTheLimit() async throws {
        defer { cleanUp() }
        let url = try transcript([
            F.prompt("u1", "One"), F.assistant("a1", [F.text("Reply one")], at: 1),
            F.turnDuration("s1", milliseconds: 1_000, at: 1),
            F.prompt("u2", "Two", at: 5), F.assistant("a2", [F.text("Reply two")], at: 6),
        ])
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 3))
        defer { consumer.cancel() }

        #expect(await eventually { await recorder.emissions.first?.map(\.id) == ["s1", "u2", "a2"] })
    }

    @Test func growthEmitsTheNewBlocks() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One")])
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.emissions.count == 1 })

        try append([F.assistant("a1", [F.toolUse("t1", "Bash", ["command": "ls"])], at: 1)], to: url)
        #expect(await eventually { await recorder.emissions.last?.map(\.id) == ["u1", "a1"] })

        try append([F.user("r1", content: [F.toolResult("t1", "listing")], at: 2)], to: url)
        #expect(await eventually {
            await recorder.emissions.last?.last?.kind == .tools(summary: "ran 1 shell command",
                                                                 calls: [ToolCall(name: "Bash", summary: "ls", result: "listing")])
        })
    }

    @Test func aSlowConsumerReceivesOnlyTheNewestSnapshot() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One")])
        let stream = source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10)
        try await Task.sleep(for: .milliseconds(150))
        try append([F.assistant("a1", [F.text("Reply")], at: 1)], to: url)
        try await Task.sleep(for: .milliseconds(150))
        try append([F.prompt("u2", "Two", at: 2)], to: url)
        try await Task.sleep(for: .milliseconds(150))

        var snapshots = stream.makeAsyncIterator()
        #expect(await snapshots.next()?.map(\.id) == ["u1", "a1", "u1#end", "u2"])
    }

    @Test func nothingIsEmittedAgainWhileTheTranscriptIsUnchanged() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One")])
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.emissions.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(await recorder.emissions.count == 1)
    }

    @Test func aTruncatedTranscriptIsReadAgain() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One"), F.assistant("a1", [F.text("Reply")], at: 1)])
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.emissions.last?.map(\.id) == ["u1", "a1"] })

        _ = try transcript([F.prompt("x1", "Fresh")])
        #expect(await eventually { await recorder.emissions.last?.map(\.id) == ["x1"] })
    }

    @Test func anIDReferenceStreamsTheResolvedTranscript() async throws {
        defer { cleanUp() }
        try session(configDir: ".claude-a", project: "-proj", id: "abc", modified: F.time(0))
        let (recorder, consumer) = record(source([".claude-a"]).chat(at: AgentSessionRef(kind: .id, value: "abc"), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.emissions.first?.map(\.kind) == [.prompt("From .claude-a")] })
    }

    @Test func anUnresolvableReferenceFinishesTheStream() async {
        defer { cleanUp() }
        let (recorder, consumer) = record(source([".claude-a"]).chat(at: AgentSessionRef(kind: .id, value: "abc"), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.finished })
        #expect(await recorder.emissions.isEmpty)
    }

    @Test func anUnreadableTranscriptFinishesTheStream() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One")])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.finished })
        #expect(await recorder.emissions.isEmpty)
    }

    @Test func aTranscriptThatDisappearsFinishesTheStream() async throws {
        defer { cleanUp() }
        let url = try transcript([F.prompt("u1", "One")])
        let (recorder, consumer) = record(source().chat(at: AgentSessionRef(kind: .path, value: url.path), limit: 10))
        defer { consumer.cancel() }
        #expect(await eventually { await recorder.emissions.count == 1 })
        try FileManager.default.removeItem(at: url)
        #expect(await eventually { await recorder.finished })
    }
}
