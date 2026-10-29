import Foundation
import Testing
@testable import HerdrKit

@Suite struct TransportClientTests {
    // MARK: Discovery

    @Test func discoversTheSocketWithAStrippedEnvironmentAndCachesIt() async throws {
        let server = try FakeHerdrServer { [$0.result(agentListResult([]))] }
        defer { server.stop() }
        let runner = FakeProcessRunner(socketPath: server.path)
        let client = LiveHerdrClient.testing(runner: runner, environment: ["HOME": "/Users/test", "HERDR_SOCKET": "/x", "PATH": "/evil"])
        _ = try await client.agents(on: .local)
        _ = try await client.agents(on: .local)
        #expect(runner.invocations == [FakeProcessRunner.Invocation(
            executable: "/opt/homebrew/bin/herdr", arguments: ["status", "server"],
            environment: ["HOME": "/Users/test",
                          "PATH": "/Users/test/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"])])
        #expect(server.requests("agent.list").count == 2)
    }

    @Test func noBinaryMeansNotInstalledWithoutRunningAnything() async {
        let runner = FakeProcessRunner(socketPath: "/unused.sock")
        let client = LiveHerdrClient(runner: runner, home: "/Users/test", environment: [:], isExecutable: { _ in false })
        await #expect(throws: HerdrError.notInstalled) { _ = try await client.agents(on: .local) }
        #expect(runner.invocations.isEmpty)
    }

    @Test func aFailingStatusCommandIsUnreachable() async {
        let runner = FakeProcessRunner(.success(ProcessOutput(status: 1, stdout: Data(), stderr: Data("server not running".utf8))))
        let client = LiveHerdrClient.testing(runner: runner)
        await #expect(throws: HerdrError.unreachable("herdr status server exited with status 1")) { _ = try await client.agents(on: .local) }
    }

    @Test func statusWithoutASocketLineIsUnreachable() async {
        let runner = FakeProcessRunner(.success(ProcessOutput(status: 0, stdout: Data("status: stopped\n".utf8), stderr: Data())))
        let client = LiveHerdrClient.testing(runner: runner)
        await #expect(throws: HerdrError.unreachable("herdr status server reported no socket")) { _ = try await client.agents(on: .local) }
    }

    @Test func runnerErrorsPassThrough() async {
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(.failure(.timedOut)))
        await #expect(throws: HerdrError.timedOut) { _ = try await client.agents(on: .local) }
    }

    @Test func aConnectFailureForgetsTheSocketSoTheNextCallRediscovers() async throws {
        let server = try FakeHerdrServer { [$0.result(agentListResult([]))] }
        defer { server.stop() }
        let gone = try TemporaryDirectory()
        let runner = FakeProcessRunner(.success(.status(socket: gone.path + "/old.sock")), .success(.status(socket: server.path)))
        let client = LiveHerdrClient.testing(runner: runner)
        await #expect { _ = try await client.agents(on: .local) } throws: { error in
            if case HerdrError.unreachable = error { return true }
            return false
        }
        #expect(try await client.agents(on: .local).isEmpty)
        #expect(runner.invocations.count == 2)
    }

    // MARK: Requests

    @Test func agentsListsOverTheSocket() async throws {
        let server = try FakeHerdrServer { [$0.result(agentListResult([agentJSON(pane: "w1:p1"), agentJSON(pane: "w2:p1", status: "done")]))] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        let agents = try await client.agents(on: .local)
        #expect(agents.map(\.paneID) == [PaneID("w1:p1"), PaneID("w2:p1")])
        #expect(agents.map(\.status) == [.idle, .done])
        let request = try #require(server.requests.first)
        #expect(request.method == "agent.list")
        #expect(request.params.isEmpty)
        #expect(UUID(uuidString: request.id) != nil)
    }

    @Test func agentGetsOnePane() async throws {
        let server = try FakeHerdrServer { [$0.result(agentInfoResult(agentJSON(pane: "w3:p2", status: "blocked")))] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        let agent = try await client.agent(PaneID("w3:p2"), on: .local)
        #expect(agent.paneID == PaneID("w3:p2"))
        #expect(agent.status == .blocked)
        #expect(server.requests.map(\.method) == ["agent.get"])
        #expect(server.requests[0].params as? [String: String] == ["target": "w3:p2"])
    }

    @Test func readAsksForPlainTextAndReturnsIt() async throws {
        let server = try FakeHerdrServer { request in
            [request.result(#"{"read":{"format":"text","pane_id":"w1:p1","revision":2,"source":"recent_unwrapped","tab_id":"w1:t1","text":"line one\nline two","truncated":false,"workspace_id":"w1"},"type":"pane_read"}"#)]
        }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        let text = try await client.read(PaneID("w1:p1"), source: .recentUnwrapped, lines: 180, on: .local)
        #expect(text == "line one\nline two")
        let request = try #require(server.requests.first)
        #expect(request.method == "agent.read")
        #expect(request.params["target"] as? String == "w1:p1")
        #expect(request.params["source"] as? String == "recent_unwrapped")
        #expect(request.params["lines"] as? Int == 180)
        #expect(request.params["format"] as? String == "text")
        #expect(request.params["strip_ansi"] as? Bool == true)
    }

    @Test func focusTargetsThePane() async throws {
        let server = try FakeHerdrServer { [$0.result(#"{"type":"ok"}"#)] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        try await client.focus(PaneID("w1:p1"), on: .local)
        #expect(server.requests.map(\.method) == ["agent.focus"])
        #expect(server.requests[0].params as? [String: String] == ["target": "w1:p1"])
    }

    // MARK: Reply handling

    @Test func anErrorReplyIsRejectedWithItsCode() async throws {
        let server = try FakeHerdrServer { [$0.error(code: "agent_not_found", message: "no agent w9:p9")] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        await #expect(throws: HerdrError.rejected(code: "agent_not_found", message: "no agent w9:p9")) {
            try await client.focus(PaneID("w9:p9"), on: .local)
        }
    }

    @Test func aReplyForAnotherRequestIsUnexpected() async throws {
        let server = try FakeHerdrServer { _ in [.line(#"{"id":"someone-else","result":{"type":"ok"}}"#)] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        await #expect(throws: HerdrError.unexpectedResponse("reply id mismatch")) { try await client.focus(PaneID("w1:p1"), on: .local) }
    }

    @Test func aMalformedReplyIsUnexpected() async throws {
        let server = try FakeHerdrServer { _ in [.line("not json at all")] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        await #expect { _ = try await client.agents(on: .local) } throws: { error in
            if case HerdrError.unexpectedResponse = error { return true }
            return false
        }
    }

    @Test func aReplyOfTheWrongShapeIsUnexpected() async throws {
        let server = try FakeHerdrServer { [$0.result(#"{"type":"ok"}"#)] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        await #expect { _ = try await client.read(PaneID("w1:p1"), source: .visible, lines: 10, on: .local) } throws: { error in
            if case HerdrError.unexpectedResponse = error { return true }
            return false
        }
    }

    @Test func aSlowReplyTimesOut() async throws {
        // The reply comes long after the deadline, so a starved client still finds no reply waiting.
        let server = try FakeHerdrServer { [.pause(.seconds(60)), $0.result(agentListResult([]))] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path), requestDeadline: .milliseconds(200))
        await #expect(throws: HerdrError.timedOut) { _ = try await client.agents(on: .local) }
    }

    @Test func anOversizedReplyIsTooLarge() async throws {
        let server = try FakeHerdrServer { [$0.result(agentListResult([agentJSON(pane: "w1:p1"), agentJSON(pane: "w2:p1")]))] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path), replyCap: 200)
        await #expect(throws: HerdrError.outputTooLarge) { _ = try await client.agents(on: .local) }
    }

    @Test func defaultReplyCapAndDeadlineMatchTheDesign() {
        let settings = LiveHerdrClient.Settings()
        #expect(settings.requestDeadline == .seconds(12))
        #expect(settings.replyCap == 1 << 20)
        #expect(settings.refreshInterval == .seconds(30))
    }

    @Test func herdrHangingUpIsUnreachable() async throws {
        let server = try FakeHerdrServer { _ in [.close] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path))
        await #expect(throws: HerdrError.unreachable("herdr closed the connection")) { _ = try await client.agents(on: .local) }
    }

    @Test func cancellingACallEndsItWithoutWaitingForTheDeadline() async throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: server.path), requestDeadline: .seconds(300))
        let call = Task { try await client.agents(on: .local) }
        #expect(await eventually { server.requests.count == 1 })
        let started = ContinuousClock.now
        call.cancel()
        await #expect(throws: HerdrError.unreachable("cancelled")) { _ = try await call.value }
        #expect(ContinuousClock.now - started < .seconds(60))
    }
}
