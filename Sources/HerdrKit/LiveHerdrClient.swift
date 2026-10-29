import Foundation
import Synchronization

/// Talks to the real herdr through its CLI and its local Unix socket. The CLI only discovers the
/// socket; every API call, including prompt text, goes over the socket.
public struct LiveHerdrClient: HerdrClient {
    struct Settings: Sendable {
        var requestDeadline: Duration = .seconds(12)
        var replyCap = 1 << 20
        /// How often `events(on:)` re-lists agents to follow panes that appear or close.
        var refreshInterval: Duration = .seconds(30)
    }

    let settings: Settings
    private let runner: any ProcessRunner
    private let home: String
    private let environment: [String: String]
    private let isExecutable: @Sendable (String) -> Bool
    private let socketPath = SocketPathCache()

    public init() {
        self.init(runner: LiveProcessRunner(), home: NSHomeDirectory(), environment: ProcessInfo.processInfo.environment,
                  isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    init(runner: any ProcessRunner, home: String, environment: [String: String],
         isExecutable: @escaping @Sendable (String) -> Bool, settings: Settings = Settings()) {
        self.runner = runner
        self.home = home
        self.environment = environment
        self.isExecutable = isExecutable
        self.settings = settings
    }

    public func agents(on machine: MachineID) async throws(HerdrError) -> [AgentInfo] {
        let reply = try await withConnection { connection throws(HerdrError) in
            try connection.call("agent.list", HerdrParams.None())
        }
        return try HerdrConnection.decoding { try AgentInfo.decodeList(reply, machine: machine) }
    }

    public func agent(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) -> AgentInfo {
        let reply = try await withConnection { connection throws(HerdrError) in
            try connection.call("agent.get", HerdrParams.Target(target: pane.rawValue))
        }
        return try HerdrConnection.decoding { try AgentInfo.decodeGet(reply, machine: machine) }
    }

    public func read(_ pane: PaneID, source: ReadSource, lines: Int, on machine: MachineID) async throws(HerdrError) -> String {
        let reply = try await withConnection { connection throws(HerdrError) in
            try connection.call("agent.read", HerdrParams.Read(target: pane.rawValue, source: source.rawValue, lines: lines))
        }
        return try HerdrConnection.decode(ReadReply.self, from: reply).result.read.text
    }

    public func focus(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) {
        _ = try await withConnection { connection throws(HerdrError) in
            try connection.call("agent.focus", HerdrParams.Target(target: pane.rawValue))
        }
    }

    /// herdr answers one request per connection and then closes it, so the recheck and the prompt
    /// each get a connection of their own, the prompt's opened right after the recheck passes.
    public func send(_ text: String, to identity: AgentIdentity) async -> PromptOutcome {
        if let reason = PromptDelivery.invalidTextReason(text) { return .refused(.invalidText(reason)) }
        do {
            if let refusal = try await withConnection({ connection throws(HerdrError) in
                try PromptDelivery.recheck(identity, over: connection)
            }) {
                return .refused(refusal)
            }
            return try await withConnection { connection in
                PromptDelivery.submit(text, to: identity, over: connection)
            }
        } catch {
            // Only discovery, connecting or the recheck can throw; none of them writes the prompt.
            return .refused(error.refusal)
        }
    }

    public func events(on machine: MachineID) -> AsyncThrowingStream<HerdrEvent, any Error> {
        AsyncThrowingStream { continuation in
            let following = Task { await followStatuses(on: machine, into: continuation) }
            continuation.onTermination = { _ in following.cancel() }
        }
    }

    // MARK: Connections

    /// Runs `body` on a fresh connection that closes when it returns.
    func withConnection<T: Sendable>(_ body: @escaping @Sendable (HerdrConnection) throws(HerdrError) -> T) async throws(HerdrError) -> T {
        let socket = try LineSocket()
        defer { socket.close() }
        return try await connect(socket, then: body)
    }

    /// Connects `socket` to herdr and runs `body` on it, off the cooperative pool since both block in
    /// `poll`. Cancelling the calling task interrupts the socket. The caller closes `socket`.
    func connect<T: Sendable>(_ socket: LineSocket, then body: @escaping @Sendable (HerdrConnection) throws(HerdrError) -> T)
        async throws(HerdrError) -> T {
        let path = try await discoverSocket()
        let settings = settings
        let socketPath = socketPath
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, HerdrError>, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Result { () throws(HerdrError) -> T in
                        do throws(HerdrError) {
                            try socket.connect(to: path, deadline: .now + settings.requestDeadline)
                        } catch {
                            transportLog.error("connect to \(path, privacy: .private) failed: \(String(describing: error), privacy: .public)")
                            socketPath.forget(path)
                            throw error
                        }
                        return try body(HerdrConnection(socket: socket, requestDeadline: settings.requestDeadline, replyCap: settings.replyCap))
                    })
                }
            }
        } onCancel: {
            socket.interrupt()
        }
        return try result.get()
    }

    private func discoverSocket() async throws(HerdrError) -> String {
        if let cached = socketPath.value { return cached }
        guard let binary = HerdrInstallation.binary(home: home, isExecutable: isExecutable) else { throw .notInstalled }
        let output = try await runner.run(binary, arguments: ["status", "server"],
                                          environment: HerdrInstallation.childEnvironment(parent: environment, home: home))
        guard output.status == 0 else { throw .unreachable("herdr status server exited with status \(output.status)") }
        guard let path = HerdrInstallation.socketPath(inServerStatus: String(decoding: output.stdout, as: UTF8.self)) else {
            throw .unreachable("herdr status server reported no socket")
        }
        socketPath.remember(path)
        return path
    }

    private struct ReadReply: Decodable {
        struct Result: Decodable {
            struct Read: Decodable { let text: String }
            let read: Read
        }
        let result: Result
    }
}

/// The discovered socket path, shared by every copy of a client.
private final class SocketPathCache: Sendable {
    private let path = Mutex<String?>(nil)

    var value: String? { path.withLock { $0 } }

    func remember(_ discovered: String) { path.withLock { $0 = discovered } }

    /// Forgets `failed` unless a newer discovery already replaced it.
    func forget(_ failed: String) {
        path.withLock { if $0 == failed { $0 = nil } }
    }
}
