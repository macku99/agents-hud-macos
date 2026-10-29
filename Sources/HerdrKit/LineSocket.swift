import Foundation
import Synchronization

/// A non-blocking AF_UNIX stream connection that exchanges newline-delimited lines. Its blocking calls
/// run on one thread at a time; `interrupt()` may be called from any thread and makes the pending or
/// next call fail, so a cancelled task never waits out a deadline.
final class LineSocket: Sendable {
    private struct Descriptors {
        var socket: Int32
        var wakeRead: Int32
        var wakeWrite: Int32
        var interrupted = false
        var closed = false
    }

    private struct Buffers {
        var pending = Data()
        var bytesWritten = 0
    }

    private let descriptors: Mutex<Descriptors>
    private let buffers = Mutex(Buffers())
    let socket: Int32
    let wake: Int32

    /// Bytes the kernel has accepted from `write`, so a caller can tell whether a failed write sent anything.
    var bytesWritten: Int { buffers.withLock { $0.bytesWritten } }

    init() throws(HerdrError) {
        var wakePipe: [Int32] = [0, 0]
        guard pipe(&wakePipe) == 0 else { throw .unreachable("pipe failed: \(Self.lastError)") }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Darwin.close(wakePipe[0])
            Darwin.close(wakePipe[1])
            throw .unreachable("socket failed: \(Self.lastError)")
        }
        [fd, wakePipe[0], wakePipe[1]].forEach(setCloseOnExec)
        socket = fd
        wake = wakePipe[0]
        descriptors = Mutex(Descriptors(socket: fd, wakeRead: wakePipe[0], wakeWrite: wakePipe[1]))
        _ = fcntl(wakePipe[1], F_SETFL, fcntl(wakePipe[1], F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    deinit { close() }

    func connect(to path: String, deadline: ContinuousClock.Instant) throws(HerdrError) {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw .unreachable("socket path is too long")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        try checkInterrupted()

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected != 0 else { return }
        guard errno == EINPROGRESS else { throw .unreachable("cannot connect: \(Self.lastError)") }
        try waitUntil(.writable, deadline: deadline)
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &length)
        guard error == 0 else { throw .unreachable("cannot connect: \(Self.describe(error))") }
    }

    func write(_ data: Data, deadline: ContinuousClock.Instant) throws(HerdrError) {
        try checkInterrupted()
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { Darwin.send(socket, $0.baseAddress! + offset, data.count - offset, 0) }
            if sent > 0 {
                offset += sent
                buffers.withLock { $0.bytesWritten += sent }
                continue
            }
            switch errno {
            case EINTR: continue
            case EAGAIN: try waitUntil(.writable, deadline: deadline)
            default: throw .unreachable("write failed: \(Self.lastError)")
            }
        }
    }

    /// The next line without its newline. A line longer than `cap` bytes is `.outputTooLarge`; with no
    /// deadline the call waits until a line, end of stream or `interrupt()`.
    func readLine(deadline: ContinuousClock.Instant?, cap: Int) throws(HerdrError) -> Data {
        try checkInterrupted()
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            if let line = try takeLine(cap: cap) { return line }
            let count = read(socket, &chunk, chunk.count)
            if count > 0 {
                buffers.withLock { $0.pending.append(contentsOf: chunk[..<count]) }
                continue
            }
            if count == 0 { throw .unreachable("herdr closed the connection") }
            switch errno {
            case EINTR: continue
            case EAGAIN: try waitUntil(.readable, deadline: deadline)
            default: throw .unreachable("read failed: \(Self.lastError)")
            }
        }
    }

    func interrupt() {
        descriptors.withLock { descriptors in
            guard !descriptors.closed else { return }
            descriptors.interrupted = true
            var byte: UInt8 = 1
            _ = Darwin.write(descriptors.wakeWrite, &byte, 1)
        }
    }

    func close() {
        descriptors.withLock { descriptors in
            guard !descriptors.closed else { return }
            descriptors.closed = true
            Darwin.close(descriptors.socket)
            Darwin.close(descriptors.wakeRead)
            Darwin.close(descriptors.wakeWrite)
        }
    }

    private func checkInterrupted() throws(HerdrError) {
        if descriptors.withLock({ $0.interrupted }) { throw .unreachable("cancelled") }
    }

    private func takeLine(cap: Int) throws(HerdrError) -> Data? {
        try buffers.withLock { (buffers) throws(HerdrError) -> Data? in
            guard let newline = buffers.pending.firstIndex(of: UInt8(ascii: "\n")) else {
                if buffers.pending.count > cap { throw .outputTooLarge }
                return nil
            }
            let line = buffers.pending[buffers.pending.startIndex..<newline]
            guard line.count <= cap else { throw .outputTooLarge }
            buffers.pending.removeSubrange(...newline)
            return Data(line)
        }
    }

    private enum Readiness { case readable, writable }

    private func waitUntil(_ readiness: Readiness, deadline: ContinuousClock.Instant?) throws(HerdrError) {
        var fds = [pollfd(fd: socket, events: Int16(readiness == .readable ? POLLIN : POLLOUT), revents: 0),
                   pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
        while true {
            var timeout: Int32 = -1
            if let deadline {
                let remaining = deadline - .now
                guard remaining > .zero else { throw .timedOut }
                timeout = Int32(clamping: max(remaining.wholeMilliseconds, 1))
            }
            let ready = poll(&fds, nfds_t(fds.count), timeout)
            if ready < 0 && errno != EINTR { throw .unreachable("poll failed: \(Self.lastError)") }
            if fds[1].revents != 0 { throw .unreachable("cancelled") }
            if fds[0].revents != 0 { return }
        }
    }

    private static var lastError: String { describe(errno) }
    private static func describe(_ code: Int32) -> String { String(cString: strerror(code)) }
}

/// Keeps `fd` out of any process the app spawns. Without it a child started elsewhere in the app, by
/// code that does not close inherited descriptors, could hold a herdr connection or a CLI pipe open.
func setCloseOnExec(_ fd: Int32) {
    _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
}
