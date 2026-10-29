import Foundation
import OSLog
import Testing
@testable import HerdrKit

@Suite struct TransportSendTests {
    private static let session = AgentSessionRef(kind: .path, value: "/tmp/synthetic/session.jsonl")
    private static let identity = AgentIdentity(machine: .local, paneID: PaneID("w1:p1"), terminalID: "term-w1:p1",
                                                workspaceID: "w1", agent: "claude", session: session)
    private static let matchingAgent = agentJSON(pane: "w1:p1", status: "idle", session: session)
    private static let acknowledged = #"{"agent":\#(matchingAgent),"type":"agent_prompted"}"#

    /// A herdr that reports `current` for `agent.get` and answers `agent.prompt` with `promptReply`.
    private func herdr(current: String = matchingAgent,
                       promptReply: @escaping @Sendable (FakeHerdrServer.Request) -> [FakeHerdrServer.Step] = { [$0.result(acknowledged)] })
        throws -> FakeHerdrServer {
        try FakeHerdrServer { request in
            switch request.method {
            case "agent.get": [request.result(agentInfoResult(current))]
            case "agent.prompt": promptReply(request)
            default: [request.error(code: "unexpected_method", message: request.method)]
            }
        }
    }

    private func send(_ text: String, server: FakeHerdrServer, requestDeadline: Duration = .seconds(60)) async -> (PromptOutcome, FakeProcessRunner) {
        let runner = FakeProcessRunner(socketPath: server.path)
        let client = LiveHerdrClient.testing(runner: runner, requestDeadline: requestDeadline)
        return (await client.send(text, to: Self.identity), runner)
    }

    // MARK: Delivered

    @Test func rechecksTheAgentThenPromptsOnAFreshConnection() async throws {
        let server = try herdr()
        defer { server.stop() }
        let (outcome, _) = await send("Run the tests\nthen summarise", server: server)
        #expect(outcome == .delivered)
        #expect(server.requests.map(\.method) == ["agent.get", "agent.prompt"])
        #expect(server.requests.map(\.connection) == [0, 1])
        #expect(server.connectionCount == 2)
        #expect(server.requests[0].params as? [String: String] == ["target": "w1:p1"])
        #expect(server.requests[1].params as? [String: String] == ["target": "w1:p1", "text": "Run the tests\nthen summarise"])
    }

    @Test func deliversToAFinishedAgent() async throws {
        let server = try herdr(current: agentJSON(pane: "w1:p1", status: "done", session: Self.session))
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .delivered)
    }

    @Test(arguments: [#"{"type":"agent_prompted"}"#, #"{"agent":{"pane_id":"w1:p1"},"type":"agent_prompted"}"#])
    func aPromptedAckThatDoesNotNameTheTerminalIsUncertain(result: String) async throws {
        let server = try herdr { [$0.result(result)] }
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .uncertain("herdr did not confirm which terminal got the prompt"))
    }

    @Test func promptTextNeverReachesProcessArgumentsOrEnvironment() async throws {
        let server = try herdr()
        defer { server.stop() }
        let text = "secret-prompt-marker"
        let (outcome, runner) = await send(text, server: server)
        #expect(outcome == .delivered)
        #expect(!runner.invocations.isEmpty)
        for invocation in runner.invocations {
            #expect(!invocation.executable.contains(text))
            #expect(!invocation.arguments.contains { $0.contains(text) })
            #expect(!invocation.environment.values.contains { $0.contains(text) })
        }
    }

    // MARK: Invalid text

    @Test(arguments: [
        ("", "the prompt is empty"),
        ("a\u{0}b", "the prompt contains a NUL character"),
        (String(repeating: "a", count: 60_001), "the prompt is longer than 60000 bytes"),
        (String(repeating: "é", count: 30_001), "the prompt is longer than 60000 bytes"),
    ])
    func invalidTextIsRefusedWithoutContactingHerdr(text: String, reason: String) async throws {
        let server = try herdr()
        defer { server.stop() }
        let (outcome, runner) = await send(text, server: server)
        #expect(outcome == .refused(.invalidText(reason)))
        #expect(runner.invocations.isEmpty)
        #expect(server.connectionCount == 0)
    }

    @Test func textOfExactlySixtyThousandBytesIsSent() async throws {
        let server = try herdr()
        defer { server.stop() }
        #expect(await send(String(repeating: "a", count: 60_000), server: server).0 == .delivered)
    }

    // MARK: Refused after the recheck

    @Test(arguments: [
        agentJSON(pane: "w1:p2", workspace: "w1", session: session).replacingOccurrences(of: "term-w1:p2", with: "term-w1:p1"),
        agentJSON(pane: "w1:p1", terminal: "term-replaced", session: session),
        agentJSON(pane: "w1:p1", workspace: "w7", session: session),
        agentJSON(pane: "w1:p1", agent: "codex", session: session),
        agentJSON(pane: "w1:p1", session: AgentSessionRef(kind: .path, value: "/tmp/synthetic/other.jsonl")),
        agentJSON(pane: "w1:p1", session: AgentSessionRef(kind: .id, value: "/tmp/synthetic/session.jsonl")),
        agentJSON(pane: "w1:p1", session: nil),
    ])
    func aChangedIdentityIsRefusedWithoutPrompting(current: String) async throws {
        let server = try herdr(current: current)
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .refused(.agentChanged))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    @Test(arguments: [AgentStatus.working, .blocked, .unknown])
    func anAgentThatIsNotReadyIsRefusedWithoutPrompting(status: AgentStatus) async throws {
        let server = try herdr(current: agentJSON(pane: "w1:p1", status: status.rawValue, session: Self.session))
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .refused(.notReady(status)))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    // MARK: Refused before the write

    @Test func herdrMissingIsUnreachable() async {
        let client = LiveHerdrClient(runner: FakeProcessRunner(socketPath: "/unused.sock"), home: "/Users/test",
                                     environment: [:], isExecutable: { _ in false })
        #expect(await client.send("next", to: Self.identity) == .refused(.unreachable("herdr is not installed")))
    }

    @Test func aSocketThatCannotBeReachedIsUnreachable() async throws {
        let gone = try TemporaryDirectory()
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: gone.path + "/gone.sock"))
        let outcome = await client.send("next", to: Self.identity)
        guard case .refused(.unreachable) = outcome else {
            Issue.record("expected unreachable, got \(outcome)")
            return
        }
    }

    @Test func aFailedConnectKeepsTheSocketPathOutOfThePublicLog() async throws {
        let gone = try TemporaryDirectory()
        let path = gone.path + "/gone.sock"
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: path))
        _ = await client.send("next", to: Self.identity)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "app.itfrombit.agentshud" }
            .map(\.composedMessage)
        #expect(messages.contains { $0.contains("connect to") })
        #expect(!messages.contains { $0.contains(gone.path) })
    }

    @Test func aRecheckRejectedByHerdrIsRefused() async throws {
        let server = try FakeHerdrServer { [$0.error(code: "agent_not_found", message: "no agent in w1:p1")] }
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .refused(.rejected("agent_not_found: no agent in w1:p1")))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    @Test func aRecheckThatTimesOutIsUnreachable() async throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let outcome = await send("next", server: server, requestDeadline: .milliseconds(200)).0
        #expect(outcome == .refused(.unreachable("herdr did not answer in time")))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    @Test func aMalformedRecheckIsUnreachable() async throws {
        let server = try FakeHerdrServer { [$0.result(#"{"type":"agent_info"}"#)] }
        defer { server.stop() }
        let outcome = await send("next", server: server).0
        guard case .refused(.unreachable(let detail)) = outcome else {
            Issue.record("expected unreachable, got \(outcome)")
            return
        }
        #expect(detail.hasPrefix("unexpected reply from herdr"))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    /// herdr's socket API documents only `agent_blocked` as raised before any input reaches the pane.
    @Test func aBlockedAgentRejectionIsRefused() async throws {
        let server = try herdr { [$0.error(code: "agent_blocked", message: "refused before input")] }
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .refused(.rejected("agent_blocked: refused before input")))
        #expect(server.requests("agent.prompt").count == 1)
    }

    @Test(arguments: ["not_found", "invalid_params", "pane_not_found", "agent_not_found", "agent_prompt_failed", "internal_error"])
    func aPromptErrorNotDocumentedToPrecedeInputIsUncertain(code: String) async throws {
        let server = try herdr { [$0.error(code: code, message: "prompt failed")] }
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .uncertain("\(code): prompt failed"))
        #expect(server.requests("agent.prompt").count == 1)
    }

    // MARK: Uncertain after the write

    @Test func noAckBeforeTheDeadlineIsUncertain() async throws {
        let server = try herdr { _ in [] }
        defer { server.stop() }
        // The deadline also covers agent.get, which must succeed first, so it is not made shorter.
        let outcome = await send("next", server: server, requestDeadline: .seconds(2)).0
        #expect(outcome == .uncertain("herdr did not answer in time"))
        #expect(server.requests("agent.prompt").count == 1)
    }

    @Test func herdrHangingUpAfterThePromptIsUncertain() async throws {
        let server = try herdr { _ in [.close] }
        defer { server.stop() }
        #expect(await send("next", server: server).0 == .uncertain("herdr closed the connection"))
        #expect(server.requests("agent.prompt").count == 1)
    }

    @Test func aFailedAckIsLoggedWithItsMethodAndWithoutThePrompt() async throws {
        let server = try herdr { _ in [.close] }
        defer { server.stop() }
        let text = "secret-prompt-marker"
        _ = await send(text, server: server)
        let id = try #require(server.requests("agent.prompt").first).id

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "app.itfrombit.agentshud" }
            .map(\.composedMessage)
        let forThisPrompt = messages.filter { $0.contains(id) }
        #expect(!forThisPrompt.isEmpty)
        #expect(forThisPrompt.allSatisfy { $0.contains("agent.prompt") })
        #expect(!messages.contains { $0.contains(text) })
    }

    @Test(arguments: [
        "not json",
        #"{"id":"other-request","result":{"type":"agent_prompted"}}"#,
    ])
    func anUnreadableOrForeignAckIsUncertain(line: String) async throws {
        let server = try herdr { _ in [.line(line)] }
        defer { server.stop() }
        let outcome = await send("next", server: server).0
        guard case .uncertain = outcome else {
            Issue.record("expected uncertain, got \(outcome)")
            return
        }
        #expect(server.requests("agent.prompt").count == 1)
    }

    @Test(arguments: [
        #"{"type":"ok"}"#,
        #"{"agent":\#(agentJSON(pane: "w1:p1", terminal: "term-replaced", session: session)),"type":"agent_prompted"}"#,
    ])
    func anAckThatDoesNotConfirmThisTerminalIsUncertain(result: String) async throws {
        let server = try herdr { [$0.result(result)] }
        defer { server.stop() }
        let outcome = await send("next", server: server).0
        guard case .uncertain = outcome else {
            Issue.record("expected uncertain, got \(outcome)")
            return
        }
    }

    @Test func cancellingWhileWaitingForTheAckIsUncertain() async throws {
        let server = try herdr { _ in [] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path), requestDeadline: .seconds(300))
        let sending = Task { await client.send("next", to: Self.identity) }
        #expect(await eventually { server.requests("agent.prompt").count == 1 })
        sending.cancel()
        let outcome = await sending.value
        #expect(outcome == .uncertain("cancelled"))
        #expect(server.requests("agent.prompt").count == 1)
    }

    @Test func cancellingDuringTheRecheckRefusesWithoutPrompting() async throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path), requestDeadline: .seconds(300))
        let sending = Task { await client.send("next", to: Self.identity) }
        #expect(await eventually { server.requests("agent.get").count == 1 })
        sending.cancel()
        let outcome = await sending.value
        #expect(outcome == .refused(.unreachable("cancelled")))
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests("agent.prompt").isEmpty)
    }

    @Test func aPromptWriteThatStallsPartwayIsUncertain() async throws {
        // The fake answers agent.get, then never reads the prompt's connection, so a prompt larger
        // than the socket buffers is only partly written when the deadline passes.
        let server = try FakeHerdrServer(unreadConnections: [1]) { request in
            [request.result(agentInfoResult(Self.matchingAgent))]
        }
        defer { server.stop() }
        // The deadline also covers agent.get, which must succeed first, so it is not made shorter.
        let outcome = await send(String(repeating: "a", count: 60_000), server: server, requestDeadline: .seconds(2)).0
        #expect(outcome == .uncertain("herdr did not answer in time"))
    }

    @Test func aPromptWriteThatFailsBeforeAnyByteIsRefused() throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let socket = try LineSocket()
        defer { socket.close() }
        try socket.connect(to: server.path, deadline: .now + .seconds(60))
        socket.interrupt()
        let connection = HerdrConnection(socket: socket, requestDeadline: .seconds(60), replyCap: 1 << 20)
        #expect(PromptDelivery.submit("next", to: Self.identity, over: connection) == .refused(.unreachable("cancelled")))
        #expect(socket.bytesWritten == 0)
    }

    @Test func anUncertainSendIsNeverRetried() async throws {
        let server = try herdr { _ in [.close] }
        defer { server.stop() }
        _ = await send("next", server: server)
        try await Task.sleep(for: .milliseconds(200))
        #expect(server.requests("agent.prompt").count == 1)
        #expect(server.connectionCount == 2)
    }
}
