import Foundation
import Synchronization

/// herdr 0.9.5's `pane.agent_status_changed` is a state filter: it needs a pane and fires only for
/// the status it names, immediately if the pane is already in it and again on every entry. A live
/// feed is therefore one subscription per pane per status, held on one connection.
extension LiveHerdrClient {
    typealias EventContinuation = AsyncThrowingStream<HerdrEvent, any Error>.Continuation

    /// Subscribes to the listed panes and re-lists every refresh interval, moving to a fresh
    /// subscription when the pane set changes. With no agents it holds no connection, since an empty
    /// subscription list is untested against herdr. A failed re-list ends the stream like a broken
    /// connection does: the caller reconciles and subscribes again.
    func followStatuses(on machine: MachineID, into continuation: EventContinuation) async {
        var subscribedPanes: Set<PaneID>?
        var subscription: StatusSubscription?
        defer { subscription?.stop() }
        do {
            while !Task.isCancelled {
                let panes = Set(try await agents(on: machine).map(\.paneID))
                if panes != subscribedPanes {
                    let next = panes.isEmpty ? nil : try await subscribe(to: panes, into: continuation)
                    subscription?.stop()
                    subscription = next
                    subscribedPanes = panes
                }
                try await Task.sleep(for: settings.refreshInterval)
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func subscribe(to panes: Set<PaneID>, into continuation: EventContinuation) async throws(HerdrError) -> StatusSubscription {
        let subscriptions = panes.map(\.rawValue).sorted().flatMap { pane in
            [AgentStatus.idle, .working, .blocked, .done, .unknown].map {
                HerdrParams.Subscribe.Subscription(pane_id: pane, agent_status: $0.rawValue)
            }
        }
        let socket = try LineSocket()
        do throws(HerdrError) {
            try await connect(socket) { connection throws(HerdrError) in
                let ack = try connection.call("events.subscribe", HerdrParams.Subscribe(subscriptions: subscriptions))
                let started = try HerdrConnection.decode(SubscribeAck.self, from: ack).result.type
                guard started == "subscription_started" else { throw .unexpectedResponse("subscription not started: \(started)") }
            }
        } catch {
            socket.close()
            throw error
        }
        return StatusSubscription(socket: socket, eventCap: settings.replyCap, continuation: continuation)
    }

    private struct SubscribeAck: Decodable {
        struct Result: Decodable { let type: String }
        let result: Result
    }
}

/// One subscribed connection, read on its own thread because it waits without a deadline. A
/// connection that breaks while still wanted finishes the stream; one that was stopped stays quiet.
final class StatusSubscription: Sendable {
    private let socket: LineSocket
    private let stopped = Mutex(false)

    init(socket: LineSocket, eventCap: Int, continuation: LiveHerdrClient.EventContinuation) {
        self.socket = socket
        Thread.detachNewThread { [self] in
            defer { socket.close() }
            do throws(HerdrError) {
                while true {
                    if let event = try Self.event(in: socket.readLine(deadline: nil, cap: eventCap)) {
                        continuation.yield(event)
                    }
                }
            } catch {
                if !stopped.withLock({ $0 }) { continuation.finish(throwing: error) }
            }
        }
    }

    func stop() {
        stopped.withLock { $0 = true }
        socket.interrupt()
    }

    /// The status change in `line`; nil for other events. An error line, or `events_lost` in either
    /// form, is thrown.
    static func event(in line: Data) throws(HerdrError) -> HerdrEvent? {
        let pushed = try HerdrConnection.decode(PushedLine.self, from: line)
        if let error = pushed.error { throw .rejected(code: error.code, message: error.message) }
        // herdr documents events_lost as an error reply; an event of that name is treated the same.
        if pushed.event == "events_lost" { throw .rejected(code: "events_lost", message: "herdr dropped events") }
        guard pushed.event == "pane.agent_status_changed" else { return nil }
        let data = try HerdrConnection.decode(StatusChange.self, from: line).data
        return .agentStatusChanged(PaneID(data.pane_id), AgentStatus(rawValue: data.agent_status) ?? .unknown)
    }

    private struct PushedLine: Decodable {
        let event: String?
        let error: HerdrConnection.ErrorBody?
    }

    private struct StatusChange: Decodable {
        struct Data: Decodable {
            let pane_id: String
            let agent_status: String
        }

        let data: Data
    }
}
