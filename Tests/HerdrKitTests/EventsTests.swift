import Foundation
import Synchronization
import Testing
@testable import HerdrKit

@Suite(.timeLimit(.minutes(1))) struct TransportEventsTests {
    private static let statuses = ["idle", "working", "blocked", "done", "unknown"]

    /// A herdr whose agent list is `panes` at the time of each `agent.list`, and which acknowledges
    /// every subscription.
    private final class Herdr: Sendable {
        final class Panes: Sendable {
            let list: Mutex<[String]>
            init(_ panes: [String]) { list = Mutex(panes) }
        }

        let panes: Panes
        let server: FakeHerdrServer

        init(panes: [String], subscribe: @escaping @Sendable (FakeHerdrServer.Request) -> [FakeHerdrServer.Step] = {
            [$0.result(#"{"type":"subscription_started"}"#)]
        }) throws {
            let current = Panes(panes)
            self.panes = current
            server = try FakeHerdrServer { request in
                switch request.method {
                case "agent.list": [request.result(agentListResult(current.list.withLock { $0 }.map { agentJSON(pane: $0) }))]
                case "events.subscribe": subscribe(request)
                default: [request.error(code: "unexpected_method", message: request.method)]
                }
            }
        }

        var subscriptions: [FakeHerdrServer.Request] { server.requests("events.subscribe") }

        func push(_ line: String, toSubscription index: Int = 0) {
            server.push(line, toConnection: subscriptions[index].connection)
        }
    }

    private func statusEvent(_ pane: String, _ status: String) -> String {
        #"{"event":"pane.agent_status_changed","data":{"pane_id":"\#(pane)","workspace_id":"w1","agent":"claude","agent_status":"\#(status)"}}"#
    }

    private func events(from herdr: Herdr, refreshInterval: Duration = .seconds(30)) -> AsyncThrowingStream<HerdrEvent, any Error> {
        LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: herdr.server.path), refreshInterval: refreshInterval)
            .events(on: .local)
    }

    @Test func subscribesEveryStatusOfEveryListedPaneOnOneConnection() async throws {
        let herdr = try Herdr(panes: ["w2:p1", "w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let consumer = Task { for try await _ in stream {} }
        defer { consumer.cancel() }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        let subscriptions = try #require(herdr.subscriptions.first?.params["subscriptions"] as? [[String: String]])
        let expected = ["w1:p1", "w2:p1"].flatMap { pane in
            Self.statuses.map { ["type": "pane.agent_status_changed", "pane_id": pane, "agent_status": $0] }
        }
        #expect(subscriptions == expected)
        #expect(UUID(uuidString: herdr.subscriptions[0].id) != nil)
    }

    @Test func yieldsStatusChangesIncludingTheInitialMatches() async throws {
        let herdr = try Herdr(panes: ["w1:p1"]) { request in
            [request.result(#"{"type":"subscription_started"}"#), .line(#"{"event":"pane.agent_status_changed","data":{"pane_id":"w1:p1","workspace_id":"w1","agent":"claude","agent_status":"idle"}}"#)]
        }
        defer { herdr.server.stop() }
        var iterator = events(from: herdr).makeAsyncIterator()
        #expect(try await iterator.next() == .agentStatusChanged(PaneID("w1:p1"), .idle))
        herdr.push(#"{"event":"pane.output_matched","data":{"pane_id":"w1:p1"}}"#)
        herdr.push(statusEvent("w1:p1", "working"))
        herdr.push(statusEvent("w1:p1", "napping"))
        #expect(try await iterator.next() == .agentStatusChanged(PaneID("w1:p1"), .working))
        #expect(try await iterator.next() == .agentStatusChanged(PaneID("w1:p1"), .unknown))
    }

    @Test func resubscribesOnAFreshConnectionWhenThePaneSetChanges() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        var iterator = events(from: herdr, refreshInterval: .milliseconds(100)).makeAsyncIterator()
        #expect(await eventually { herdr.subscriptions.count == 1 })
        herdr.panes.list.withLock { $0.append("w3:p1") }
        #expect(await eventually { herdr.subscriptions.count == 2 })
        let second = herdr.subscriptions[1]
        #expect(second.connection != herdr.subscriptions[0].connection)
        let panes = Set((second.params["subscriptions"] as? [[String: String]] ?? []).compactMap { $0["pane_id"] })
        #expect(panes == ["w1:p1", "w3:p1"])
        herdr.push(statusEvent("w3:p1", "done"), toSubscription: 1)
        #expect(try await iterator.next() == .agentStatusChanged(PaneID("w3:p1"), .done))
        #expect(await eventually { herdr.server.clientClosed(herdr.subscriptions[0].connection) })
    }

    @Test func keepsTheSubscriptionWhileThePaneSetIsUnchanged() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr, refreshInterval: .milliseconds(50))
        let consumer = Task { for try await _ in stream {} }
        defer { consumer.cancel() }
        #expect(await eventually { herdr.server.requests("agent.list").count >= 4 })
        #expect(herdr.subscriptions.count == 1)
    }

    @Test func withNoAgentsItWaitsForOneBeforeSubscribing() async throws {
        let herdr = try Herdr(panes: [])
        defer { herdr.server.stop() }
        let stream = events(from: herdr, refreshInterval: .milliseconds(50))
        let consumer = Task { for try await _ in stream {} }
        defer { consumer.cancel() }
        #expect(await eventually { herdr.server.requests("agent.list").count >= 2 })
        #expect(herdr.subscriptions.isEmpty)
        herdr.panes.list.withLock { $0 = ["w4:p1"] }
        #expect(await eventually { herdr.subscriptions.count == 1 })
    }

    @Test func aBrokenConnectionEndsTheStreamWithAnError() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let reading = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        herdr.server.closeConnection(herdr.subscriptions[0].connection)
        await #expect(throws: HerdrError.unreachable("herdr closed the connection")) { _ = try await reading.value }
    }

    @Test func lostEventsEndTheStreamWithAnError() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let reading = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        herdr.push(#"{"id":"\#(herdr.subscriptions[0].id)","error":{"code":"events_lost","message":"subscriber fell behind"}}"#)
        await #expect(throws: HerdrError.rejected(code: "events_lost", message: "subscriber fell behind")) { _ = try await reading.value }
    }

    @Test func lostEventsPushedAsAnEventEndTheStreamWithAnError() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let reading = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        herdr.push(#"{"event":"events_lost","data":{"dropped":12}}"#)
        // Were the envelope ignored, this event would come out instead of the error.
        herdr.push(statusEvent("w1:p1", "idle"))
        await #expect(throws: HerdrError.rejected(code: "events_lost", message: "herdr dropped events")) { _ = try await reading.value }
    }

    @Test func aMalformedEventEndsTheStreamWithAnError() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let reading = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        herdr.push("{not json")
        await #expect { _ = try await reading.value } throws: { error in
            if case HerdrError.unexpectedResponse = error { return true }
            return false
        }
    }

    @Test func aRejectedSubscriptionEndsTheStreamWithAnError() async throws {
        let herdr = try Herdr(panes: ["w1:p1"]) { [$0.error(code: "invalid_params", message: "bad subscription")] }
        defer { herdr.server.stop() }
        var iterator = events(from: herdr).makeAsyncIterator()
        await #expect(throws: HerdrError.rejected(code: "invalid_params", message: "bad subscription")) { _ = try await iterator.next() }
    }

    @Test func anUnreachableHerdrEndsTheStreamWithAnError() async throws {
        let gone = try TemporaryDirectory()
        let client = LiveHerdrClient.testing(runner: FakeProcessRunner(socketPath: gone.path + "/gone.sock"))
        var iterator = client.events(on: .local).makeAsyncIterator()
        await #expect { _ = try await iterator.next() } throws: { error in
            if case HerdrError.unreachable = error { return true }
            return false
        }
    }

    @Test func cancellingTheConsumerClosesTheConnection() async throws {
        let herdr = try Herdr(panes: ["w1:p1"])
        defer { herdr.server.stop() }
        let stream = events(from: herdr)
        let consumer = Task { for try await _ in stream {} }
        #expect(await eventually { herdr.subscriptions.count == 1 })
        consumer.cancel()
        #expect(await eventually { herdr.server.clientClosed(herdr.subscriptions[0].connection) })
    }
}
