import Foundation
import os

/// Failed connects, and failed requests by method and request id; never params, replies or the socket path.
let transportLog = Logger(subsystem: "app.itfrombit.agentshud", category: "transport")

/// herdr's request/reply protocol on one connected socket: `{"id","method","params"}` lines out,
/// replies matched by id. Each request gets its own deadline, covering its write and its reply.
struct HerdrConnection {
    struct PendingReply {
        let method: String
        let id: String
        let deadline: ContinuousClock.Instant
    }

    let socket: LineSocket
    let requestDeadline: Duration
    let replyCap: Int

    func call(_ method: String, _ params: some Encodable) throws(HerdrError) -> Data {
        try reply(to: send(method, params))
    }

    func send(_ method: String, _ params: some Encodable) throws(HerdrError) -> PendingReply {
        let pending = PendingReply(method: method, id: UUID().uuidString, deadline: .now + requestDeadline)
        do {
            try socket.write(Self.encodeLine(Request(id: pending.id, method: method, params: params)), deadline: pending.deadline)
        } catch {
            transportLog.error("\(method, privacy: .public) \(pending.id, privacy: .public) write failed after \(socket.bytesWritten, privacy: .public) bytes on this connection: \(String(describing: error), privacy: .public)")
            throw error
        }
        return pending
    }

    /// The reply line to `pending`. A reply carrying `error` is `.rejected`.
    func reply(to pending: PendingReply) throws(HerdrError) -> Data {
        let line: Data
        do {
            line = try socket.readLine(deadline: pending.deadline, cap: replyCap)
        } catch {
            transportLog.error("\(pending.method, privacy: .public) \(pending.id, privacy: .public) reply failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        let header = try Self.decode(ReplyHeader.self, from: line)
        guard header.id == pending.id else { throw .unexpectedResponse("reply id mismatch") }
        if let error = header.error { throw .rejected(code: error.code, message: error.message) }
        return line
    }

    static func encodeLine(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // Encoding plain structs of strings, numbers and bools cannot fail.
        return try! encoder.encode(value) + Data("\n".utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(HerdrError) -> T {
        try decoding { try JSONDecoder().decode(type, from: data) }
    }

    /// Runs a reply decoder, reporting any failure as `.unexpectedResponse`.
    static func decoding<T>(_ decode: () throws -> T) throws(HerdrError) -> T {
        do {
            return try decode()
        } catch let error as HerdrError {
            throw error
        } catch {
            throw .unexpectedResponse(String(describing: error))
        }
    }

    private struct Request<Params: Encodable>: Encodable {
        let id: String
        let method: String
        let params: Params
    }

    struct ErrorBody: Decodable {
        let code: String
        let message: String
    }

    private struct ReplyHeader: Decodable {
        let id: String?
        let error: ErrorBody?
    }
}

/// Request parameters in herdr's wire shape (see `herdr api schema --json`).
enum HerdrParams {
    struct None: Encodable {}

    struct Target: Encodable {
        let target: String
    }

    struct Read: Encodable {
        let target: String
        let source: String
        let lines: Int
        let format = "text"
        let strip_ansi = true
    }

    struct Prompt: Encodable {
        let target: String
        let text: String
    }

    struct Subscribe: Encodable {
        struct Subscription: Encodable, Hashable {
            var type = "pane.agent_status_changed"
            let pane_id: String
            let agent_status: String
        }

        let subscriptions: [Subscription]
    }
}
