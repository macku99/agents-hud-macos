import Foundation
import Synchronization
import Testing
@testable import HerdrKit

/// Runs system tools only; nothing here starts herdr.
@Suite struct TransportProcessRunnerTests {
    /// A deadline for runs that must not time out, generous so a loaded machine cannot trip it.
    private static let ample: Duration = .seconds(60)

    @Test func defaultLimitsAreTwelveSecondsAndTheOutputCaps() {
        let runner = LiveProcessRunner()
        #expect(runner.deadline == .seconds(12))
        #expect(runner.stdoutCap == 1 << 20)
        #expect(runner.stderrCap == 64 << 10)
    }

    @Test func passesArgumentsAndCapturesStdoutStderrAndStatus() async throws {
        let output = try await LiveProcessRunner(deadline: Self.ample).run(
            "/bin/sh", arguments: ["-c", "echo \"$0 $1\"; echo oops >&2; exit 3", "one", "two"], environment: [:])
        #expect(String(decoding: output.stdout, as: UTF8.self) == "one two\n")
        #expect(String(decoding: output.stderr, as: UTF8.self) == "oops\n")
        #expect(output.status == 3)
    }

    @Test func childSeesExactlyTheGivenEnvironment() async throws {
        let environment = HerdrInstallation.childEnvironment(
            parent: ["HERDR_SOCKET": "/elsewhere.sock", "HERDR_ENV": "1", "LANG": "C", "PATH": "/evil"], home: "/Users/me")
        let output = try await LiveProcessRunner(deadline: Self.ample).run("/usr/bin/env", arguments: [], environment: environment)
        let lines = Set(String(decoding: output.stdout, as: UTF8.self).split(separator: "\n").map(String.init))
        #expect(lines == ["LANG=C", "PATH=/Users/me/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"])
    }

    @Test func killsTheWholeProcessGroupAtTheDeadline() async throws {
        let directory = try TemporaryDirectory()
        let pidFile = directory.path + "/sleeper.pid"
        // Long enough for the shell to record its background sleeper first, far shorter than the sleep.
        let runner = LiveProcessRunner(deadline: .seconds(3))
        let started = ContinuousClock.now
        await #expect(throws: HerdrError.timedOut) {
            _ = try await runner.run("/bin/sh", arguments: ["-c", "/bin/sleep 300 & echo $! > \(pidFile); wait"], environment: [:])
        }
        #expect(ContinuousClock.now - started < .seconds(120))
        let grandchild = try #require(pid_t(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(await processEnds(grandchild))
    }

    @Test func cancellingKillsTheWholeProcessGroupPromptly() async throws {
        let directory = try TemporaryDirectory()
        let pidFile = directory.path + "/sleeper.pid"
        let runner = LiveProcessRunner(deadline: .seconds(300))
        let running = Task {
            try await runner.run("/bin/sh", arguments: ["-c", "/bin/sleep 600 & echo $! > \(pidFile); wait"], environment: [:])
        }
        #expect(await eventually { FileManager.default.fileExists(atPath: pidFile) })
        let started = ContinuousClock.now
        running.cancel()
        await #expect(throws: HerdrError.unreachable("cancelled")) { _ = try await running.value }
        #expect(ContinuousClock.now - started < .seconds(120))
        let grandchild = try #require(pid_t(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(await processEnds(grandchild))
    }

    @Test func aTaskCancelledBeforeRunningNeverAttemptsTheSpawn() async {
        // A spawn of a missing binary would fail as .notInstalled, so .unreachable("cancelled")
        // shows the run stopped before posix_spawn, with no race against a started child.
        let running = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiveProcessRunner().run("/nonexistent/herdr", arguments: [], environment: [:])
        }
        await #expect(throws: HerdrError.unreachable("cancelled")) { _ = try await running.value }
    }

    private final class ControlCalls: Sendable {
        let list = Mutex<[String]>([])

        func control(exited: Int32?) -> LiveProcessRunner.ChildGroup.Control {
            .init(killGroup: { pid in self.list.withLock { $0.append("kill \(pid)") } },
                  reapIfExited: { _ in exited },
                  reap: { pid in self.list.withLock { $0.append("reap \(pid)") } })
        }
    }

    @Test func aRunningChildIsKilledThenReapedOnce() {
        let calls = ControlCalls()
        let child = LiveProcessRunner.ChildGroup(control: calls.control(exited: nil))
        child.started(4242)
        child.killAndReap()
        child.killAndReap()
        #expect(calls.list.withLock { $0 } == ["kill 4242", "reap 4242"])
    }

    @Test func aChildAlreadyReapedIsNeverSignalledOrWaitedOnAgain() throws {
        let calls = ControlCalls()
        let child = LiveProcessRunner.ChildGroup(control: calls.control(exited: 0))
        child.started(4242)
        #expect(try child.reapIfExited(4242) == 0)
        child.cancel()
        child.killAndReap()
        #expect(calls.list.withLock { $0 }.isEmpty)
    }

    @Test func outputPipesAreCloseOnExec() throws {
        let pipe = try LiveProcessRunner.makePipe()
        defer {
            close(pipe.read)
            close(pipe.write)
        }
        #expect(fcntl(pipe.read, F_GETFD) & FD_CLOEXEC != 0)
        #expect(fcntl(pipe.write, F_GETFD) & FD_CLOEXEC != 0)
    }

    @Test func stdoutUpToTheCapIsKept() async throws {
        let runner = LiveProcessRunner(deadline: Self.ample, stdoutCap: 1000)
        let output = try await runner.run("/bin/sh", arguments: ["-c", "head -c 1000 /dev/zero"], environment: [:])
        #expect(output.stdout.count == 1000)
    }

    @Test func stdoutPastTheCapIsTooLarge() async {
        let runner = LiveProcessRunner(deadline: Self.ample, stdoutCap: 1000)
        await #expect(throws: HerdrError.outputTooLarge) {
            _ = try await runner.run("/bin/sh", arguments: ["-c", "head -c 1001 /dev/zero"], environment: [:])
        }
    }

    @Test func endlessStdoutStopsAtTheCapInsteadOfTheDeadline() async {
        // Had the cap not stopped it, `yes` would run into the deadline and throw .timedOut instead.
        let runner = LiveProcessRunner(deadline: Self.ample)
        await #expect(throws: HerdrError.outputTooLarge) {
            _ = try await runner.run("/usr/bin/yes", arguments: [], environment: [:])
        }
    }

    @Test func stderrPastItsCapIsTooLarge() async {
        let runner = LiveProcessRunner(deadline: Self.ample, stderrCap: 100)
        await #expect(throws: HerdrError.outputTooLarge) {
            _ = try await runner.run("/bin/sh", arguments: ["-c", "head -c 101 /dev/zero >&2"], environment: [:])
        }
    }

    @Test func missingExecutableIsNotInstalled() async {
        await #expect(throws: HerdrError.notInstalled) {
            _ = try await LiveProcessRunner().run("/nonexistent/herdr", arguments: [], environment: [:])
        }
    }

    /// A killed process stays visible until launchd reaps it, which a loaded machine can delay.
    private func processEnds(_ pid: pid_t) async -> Bool {
        await eventually { kill(pid, 0) != 0 }
    }
}

/// A short-named temp directory, removed by `remove()` or on deinit. Short because a Unix socket path inside it must
/// fit in `sun_path`.
final class TemporaryDirectory: Sendable {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path
        path = base + "/hk-" + UUID().uuidString.prefix(8)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    }

    deinit { remove() }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}
