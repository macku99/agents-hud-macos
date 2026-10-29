import Foundation
import Synchronization

struct ProcessOutput: Sendable, Equatable {
    var status: Int32
    var stdout: Data
    var stderr: Data
}

/// Runs a herdr CLI command to completion.
protocol ProcessRunner: Sendable {
    func run(_ executable: String, arguments: [String], environment: [String: String]) async throws(HerdrError) -> ProcessOutput
}

/// Runs the child in its own process group so that a deadline, an output cap or cancelling the calling
/// task kills everything it started, not just the direct child.
struct LiveProcessRunner: ProcessRunner {
    var deadline: Duration = .seconds(12)
    var stdoutCap = 1 << 20
    var stderrCap = 64 << 10

    func run(_ executable: String, arguments: [String], environment: [String: String]) async throws(HerdrError) -> ProcessOutput {
        let child = ChildGroup()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<ProcessOutput, HerdrError>, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Result { () throws(HerdrError) in
                        try runBlocking(executable, arguments: arguments, environment: environment, child: child)
                    })
                }
            }
        } onCancel: {
            child.cancel()
        }
        return try result.get()
    }

    /// The running child's process group, killable from the cancellation handler. The pid lives only
    /// in the locked state: it is cleared there in the same critical section that reaps the child, and
    /// every kill or blocking reap reads it from there, so none can reach a reaped and possibly reused pid.
    final class ChildGroup: Sendable {
        /// The system calls a child group makes, replaceable so tests can watch them.
        struct Control: Sendable {
            var killGroup: @Sendable (pid_t) -> Void
            /// The child's wait status if it has exited, without blocking.
            var reapIfExited: @Sendable (pid_t) throws(HerdrError) -> Int32?
            var reap: @Sendable (pid_t) -> Void

            static let live = Control(
                killGroup: { kill(-$0, SIGKILL) },
                reapIfExited: { (pid) throws(HerdrError) -> Int32? in
                    var status: Int32 = 0
                    let reaped = waitpid(pid, &status, WNOHANG)
                    if reaped == pid { return status }
                    if reaped < 0 && errno != EINTR { throw .unreachable("waitpid failed: \(String(cString: strerror(errno)))") }
                    return nil
                },
                reap: { pid in
                    var ignored: Int32 = 0
                    while waitpid(pid, &ignored, 0) < 0 && errno == EINTR {}
                })
        }

        private let control: Control
        private let state = Mutex<(pid: pid_t?, cancelled: Bool)>((nil, false))

        init(control: Control = .live) {
            self.control = control
        }

        var cancelled: Bool { state.withLock { $0.cancelled } }

        func cancel() {
            state.withLock { state in
                state.cancelled = true
                if let pid = state.pid { control.killGroup(pid) }
            }
        }

        func started(_ pid: pid_t) {
            state.withLock { state in
                state.pid = pid
                if state.cancelled { control.killGroup(pid) }
            }
        }

        func reapIfExited(_ pid: pid_t) throws(HerdrError) -> Int32? {
            try state.withLock { (state) throws(HerdrError) -> Int32? in
                let status = try control.reapIfExited(pid)
                if status != nil { state.pid = nil }
                return status
            }
        }

        /// Kills and reaps the child unless it has already been reaped.
        func killAndReap() {
            let pid = state.withLock { state in
                defer { state.pid = nil }
                return state.pid
            }
            guard let pid else { return }
            // The unreaped child, even as a zombie, keeps its pid and group id reserved until `reap`.
            control.killGroup(pid)
            control.reap(pid)
        }
    }

    private func runBlocking(_ executable: String, arguments: [String], environment: [String: String],
                             child: ChildGroup) throws(HerdrError) -> ProcessOutput {
        guard !child.cancelled else { throw .unreachable("cancelled") }
        let end = ContinuousClock.now + deadline
        let stdoutPipe = try Self.makePipe()
        defer { close(stdoutPipe.read) }
        let stderrPipe: (read: Int32, write: Int32)
        do {
            stderrPipe = try Self.makePipe()
        } catch {
            close(stdoutPipe.write)
            throw error
        }
        defer { close(stderrPipe.read) }

        let pid: pid_t
        do {
            defer {
                close(stdoutPipe.write)
                close(stderrPipe.write)
            }
            pid = try spawn(executable, arguments: arguments, environment: environment, stdout: stdoutPipe.write, stderr: stderrPipe.write)
        }
        child.started(pid)

        var streams = [Stream(fd: stdoutPipe.read, cap: stdoutCap), Stream(fd: stderrPipe.read, cap: stderrCap)]
        do throws(HerdrError) {
            try drain(&streams, until: end)
            let status = try waitForExit(pid, until: end, child: child)
            guard !child.cancelled else { throw .unreachable("cancelled") }
            return ProcessOutput(status: status, stdout: streams[0].data, stderr: streams[1].data)
        } catch {
            child.killAndReap()
            throw error
        }
    }

    private struct Stream {
        let fd: Int32
        let cap: Int
        var data = Data()
        var open = true
    }

    private func drain(_ streams: inout [Stream], until end: ContinuousClock.Instant) throws(HerdrError) {
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
        while streams.contains(where: \.open) {
            let remaining = end - ContinuousClock.now
            guard remaining > .zero else { throw .timedOut }
            var fds = streams.map { pollfd(fd: $0.open ? $0.fd : -1, events: Int16(POLLIN), revents: 0) }
            let ready = poll(&fds, nfds_t(fds.count), Int32(clamping: remaining.wholeMilliseconds))
            if ready < 0 && errno != EINTR { throw .unreachable("poll failed: \(String(cString: strerror(errno)))") }
            for index in streams.indices where streams[index].open && fds[index].revents != 0 {
                let count = read(streams[index].fd, &buffer, buffer.count)
                if count > 0 {
                    streams[index].data.append(contentsOf: buffer[..<count])
                    if streams[index].data.count > streams[index].cap { throw .outputTooLarge }
                } else if count == 0 || errno != EINTR && errno != EAGAIN {
                    streams[index].open = false
                }
            }
        }
    }

    private func waitForExit(_ pid: pid_t, until end: ContinuousClock.Instant, child: ChildGroup) throws(HerdrError) -> Int32 {
        var status: Int32 = 0
        while true {
            if let exited = try child.reapIfExited(pid) {
                status = exited
                break
            }
            guard ContinuousClock.now < end else { throw .timedOut }
            usleep(5_000)
        }
        // WIFEXITED/WEXITSTATUS are macros Swift cannot import.
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private func spawn(_ executable: String, arguments: [String], environment: [String: String],
                       stdout: Int32, stderr: Int32) throws(HerdrError) -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr, 2)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let error = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        switch error {
        case 0: return pid
        case ENOENT: throw .notInstalled
        default: throw .unreachable("cannot start \(executable): \(String(cString: strerror(error)))")
        }
    }

    static func makePipe() throws(HerdrError) -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw .unreachable("pipe failed: \(String(cString: strerror(errno)))") }
        fds.forEach(setCloseOnExec)
        _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)
        return (fds[0], fds[1])
    }
}

extension Duration {
    var wholeMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
