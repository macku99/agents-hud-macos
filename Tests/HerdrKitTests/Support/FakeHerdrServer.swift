import Foundation
import Synchronization
@testable import HerdrKit

/// A scripted stand-in for herdr's Unix socket, listening in a temp directory. Each line a client
/// writes is recorded and handed to `respond`, whose steps are played back on that connection.
/// Like herdr 0.9.5, it closes a connection once it has answered a request; only `events.subscribe`
/// keeps its connection open, and a request that gets no reply leaves the connection silent. Call `stop()` when done; it ends the server's threads.
final class FakeHerdrServer: Sendable {
    enum Step: Sendable {
        /// Writes the text followed by a newline.
        case line(String)
        /// Writes the bytes exactly, with no newline added.
        case raw(Data)
        case pause(Duration)
        /// Closes the connection.
        case close
    }

    struct Request: Sendable {
        let connection: Int
        let line: String

        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:] }
        var id: String { json["id"] as? String ?? "" }
        var method: String { json["method"] as? String ?? "" }
        var params: [String: Any] { json["params"] as? [String: Any] ?? [:] }
    }

    private struct State {
        var requests: [Request] = []
        /// Accepted connections in order; -1 once closed.
        var connections: [Int32] = []
        var closedByClient: Set<Int> = []
        var stopped = false
    }

    let path: String
    private let directory: TemporaryDirectory
    private let listener: Int32
    private let respond: @Sendable (Request) -> [Step]
    /// Connections, by accept order, that are accepted but never read, as a stalled herdr would leave them.
    private let unreadConnections: Set<Int>
    private let state = Mutex(State())

    init(unreadConnections: Set<Int> = [], respond: @escaping @Sendable (Request) -> [Step]) throws {
        directory = try TemporaryDirectory()
        path = directory.path + "/s.sock"
        self.respond = respond
        self.unreadConnections = unreadConnections
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = path
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 16) == 0 else {
            close(listener)
            throw POSIXError(.EADDRNOTAVAIL)
        }
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var connectionCount: Int { state.withLock { $0.connections.count } }

    func requests(_ method: String) -> [Request] { requests.filter { $0.method == method } }

    /// Writes `line` and a newline to an accepted connection, as herdr does when it pushes an event.
    func push(_ line: String, toConnection connection: Int) {
        guard let fd = openConnection(connection) else { return }
        write(Data((line + "\n").utf8), to: fd)
    }

    func closeConnection(_ connection: Int) {
        guard let fd = openConnection(connection) else { return }
        shutdown(fd, SHUT_RDWR)
    }

    func clientClosed(_ connection: Int) -> Bool { state.withLock { $0.closedByClient.contains(connection) } }

    func stop() {
        let connections = state.withLock { state in
            state.stopped = true
            return state.connections
        }
        connections.filter { $0 >= 0 }.forEach { shutdown($0, SHUT_RDWR) }
        // Threads still pausing in a scripted reply keep the server alive past the test, possibly
        // until the test process exits, so the directory cannot wait for deinit.
        directory.remove()
    }

    private func openConnection(_ connection: Int) -> Int32? {
        state.withLock { state in
            guard state.connections.indices.contains(connection), state.connections[connection] >= 0 else { return nil }
            return state.connections[connection]
        }
    }

    /// Polls rather than blocking in `accept`, which closing or shutting down the listener does not
    /// reliably interrupt on Darwin.
    private func acceptLoop() {
        defer { close(listener) }
        while !state.withLock({ $0.stopped }) {
            var listening = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&listening, 1, 50) > 0 else { continue }
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { continue }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let index = state.withLock { state in
                state.connections.append(fd)
                return state.connections.count - 1
            }
            Thread.detachNewThread { [self] in serve(fd, index: index) }
        }
    }

    private func serve(_ fd: Int32, index: Int) {
        defer {
            state.withLock { $0.connections[index] = -1 }
            close(fd)
        }
        if unreadConnections.contains(index) {
            while !state.withLock({ $0.stopped }) { Thread.sleep(forTimeInterval: 0.05) }
            return
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                state.withLock { state in
                    if !state.stopped { state.closedByClient.insert(index) }
                }
                return
            }
            buffer.append(contentsOf: chunk[..<count])
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let request = Request(connection: index, line: String(decoding: buffer[..<newline], as: UTF8.self))
                buffer.removeSubrange(...newline)
                state.withLock { $0.requests.append(request) }
                var replied = false
                for step in respond(request) {
                    switch step {
                    case .line(let text): write(Data((text + "\n").utf8), to: fd); replied = true
                    case .raw(let data): write(data, to: fd); replied = true
                    case .pause(let duration): Thread.sleep(forTimeInterval: Double(duration.wholeMilliseconds) / 1000)
                    case .close: return
                    }
                }
                if replied && request.method != "events.subscribe" { return }
            }
        }
    }

    private func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = send(fd, bytes.baseAddress! + offset, bytes.count - offset, 0)
                guard sent > 0 else { return }
                offset += sent
            }
        }
    }
}

extension FakeHerdrServer.Request {
    /// A success reply to this request with `result` as its raw JSON.
    func result(_ result: String) -> FakeHerdrServer.Step {
        .line(#"{"id":"\#(id)","result":\#(result)}"#)
    }

    func error(code: String, message: String) -> FakeHerdrServer.Step {
        .line(#"{"id":"\#(id)","error":{"code":"\#(code)","message":"\#(message)"}}"#)
    }
}

/// Polls `condition` until it holds, giving up after `limit`. The limit is long because it only
/// matters when a test is failing, and a loaded machine can stall a test for seconds.
func eventually(within limit: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
