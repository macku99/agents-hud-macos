import Foundation
import Testing
@testable import HerdrKit

@Suite struct TransportLineSocketTests {
    /// A deadline for operations that must succeed; generous so a loaded machine cannot trip it.
    private func soon(_ duration: Duration = .seconds(60)) -> ContinuousClock.Instant { .now + duration }

    private func text(_ line: Data) -> String { String(decoding: line, as: UTF8.self) }

    private func connect(_ path: String) throws -> LineSocket {
        let socket = try LineSocket()
        try socket.connect(to: path, deadline: soon())
        return socket
    }

    @Test func writesALineAndReadsTheReply() throws {
        let server = try FakeHerdrServer { _ in [.line("pong")] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(text(try socket.readLine(deadline: soon(), cap: 1 << 20)) == "pong")
        #expect(server.requests.map(\.line) == ["ping"])
        #expect(socket.bytesWritten == 5)
    }

    @Test func joinsALineThatArrivesInPieces() throws {
        let server = try FakeHerdrServer { _ in [.raw(Data("po".utf8)), .pause(.milliseconds(50)), .raw(Data("ng\n".utf8))] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(text(try socket.readLine(deadline: soon(), cap: 1 << 20)) == "pong")
    }

    @Test func splitsSeveralLinesThatArriveTogether() throws {
        let server = try FakeHerdrServer { _ in [.raw(Data("one\ntwo\nthr".utf8)), .raw(Data("ee\n".utf8))] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("go\n".utf8), deadline: soon())
        let lines = try (0..<3).map { _ in text(try socket.readLine(deadline: soon(), cap: 1 << 20)) }
        #expect(lines == ["one", "two", "three"])
    }

    @Test func aSilentServerTimesOutAtTheDeadline() throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        let started = ContinuousClock.now
        #expect(throws: HerdrError.timedOut) { try socket.readLine(deadline: .now + .milliseconds(200), cap: 1 << 20) }
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    @Test func aLineLongerThanTheCapIsTooLarge() throws {
        let server = try FakeHerdrServer { _ in [.line(String(repeating: "x", count: 101))] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(throws: HerdrError.outputTooLarge) { try socket.readLine(deadline: soon(), cap: 100) }
    }

    @Test func endlessOutputWithoutANewlineStopsAtTheCap() throws {
        let server = try FakeHerdrServer { _ in [.raw(Data(repeating: UInt8(ascii: "x"), count: 300_000))] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(throws: HerdrError.outputTooLarge) { try socket.readLine(deadline: soon(), cap: 100_000) }
    }

    @Test func aLineExactlyAtTheCapIsKept() throws {
        let server = try FakeHerdrServer { _ in [.line(String(repeating: "x", count: 100))] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(try socket.readLine(deadline: soon(), cap: 100).count == 100)
    }

    @Test func endOfStreamBeforeANewlineIsUnreachable() throws {
        let server = try FakeHerdrServer { _ in [.raw(Data("half".utf8)), .close] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        try socket.write(Data("ping\n".utf8), deadline: soon())
        #expect(throws: HerdrError.unreachable("herdr closed the connection")) { try socket.readLine(deadline: soon(), cap: 1 << 20) }
    }

    @Test func connectingToAMissingSocketIsUnreachable() throws {
        let directory = try TemporaryDirectory()
        #expect {
            try connect(directory.path + "/none.sock")
        } throws: { error in
            if case HerdrError.unreachable = error { return true }
            return false
        }
    }

    @Test func aPathTooLongForSunPathFailsBeforeConnecting() throws {
        let path = "/tmp/" + String(repeating: "p", count: 115)
        #expect(throws: HerdrError.unreachable("socket path is too long")) {
            try connect(path)
        }
    }

    @Test func interruptEndsAReadWithNoDeadline() async throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            socket.interrupt()
        }
        #expect(throws: HerdrError.unreachable("cancelled")) { try socket.readLine(deadline: nil, cap: 1 << 20) }
    }

    @Test func afterAnInterruptNothingIsWritten() throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let socket = try connect(server.path)
        defer { socket.close() }
        socket.interrupt()
        #expect(throws: HerdrError.unreachable("cancelled")) { try socket.write(Data("ping\n".utf8), deadline: soon()) }
        #expect(socket.bytesWritten == 0)
    }

    @Test func descriptorsAreCloseOnExec() throws {
        let socket = try LineSocket()
        defer { socket.close() }
        #expect(fcntl(socket.socket, F_GETFD) & FD_CLOEXEC != 0)
        #expect(fcntl(socket.wake, F_GETFD) & FD_CLOEXEC != 0)
    }

    @Test func closingIsSeenByTheServer() async throws {
        let server = try FakeHerdrServer { _ in [] }
        defer { server.stop() }
        let socket = try connect(server.path)
        try socket.write(Data("hello\n".utf8), deadline: soon())
        #expect(await eventually { server.requests.count == 1 })
        socket.close()
        #expect(await eventually { server.clientClosed(0) })
    }
}
