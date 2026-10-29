import Foundation
import Testing
@testable import HUDApp

@MainActor
@Suite struct OverlayAlertTimersTests {
    /// A scheduler driven by hand: actions run when `advance(by:)` passes their due time.
    @MainActor
    private final class ManualScheduler: OverlayController.AlertTimers.Scheduler {
        private struct Pending {
            let due: Duration
            let action: @MainActor () -> Void
            var cancelled = false
        }

        private var now: Duration = .zero
        private var pending: [Int: Pending] = [:]
        private var nextID = 0

        func run(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> OverlayController.AlertTimers.Cancel {
            let id = nextID
            nextID += 1
            pending[id] = Pending(due: now + delay, action: action)
            return OverlayController.AlertTimers.Cancel { [weak self] in self?.pending[id]?.cancelled = true }
        }

        func advance(by duration: Duration) {
            now += duration
            let due = pending.filter { $0.value.due <= now }.sorted { $0.value.due < $1.value.due }
            for (id, entry) in due {
                pending[id] = nil
                if !entry.cancelled { entry.action() }
            }
        }
    }

    private let scheduler = ManualScheduler()
    private let first = UUID()
    private let second = UUID()

    private func makeTimers(dismissed: @escaping @MainActor (UUID) -> Void) -> OverlayController.AlertTimers {
        OverlayController.AlertTimers(scheduler: scheduler, dismiss: dismissed)
    }

    @Test func dismissesAnAlertEightSecondsAfterItShows() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        scheduler.advance(by: .milliseconds(7_999))
        #expect(dismissed.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(dismissed == [first])
    }

    @Test func eachAlertHasItsOwnTimer() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        scheduler.advance(by: .seconds(3))
        timers.show([first, second])
        scheduler.advance(by: .seconds(5))
        #expect(dismissed == [first])
        scheduler.advance(by: .seconds(3))
        #expect(dismissed == [first, second])
    }

    @Test func showingTheSameAlertsAgainKeepsTheirTimers() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        scheduler.advance(by: .seconds(5))
        timers.show([first])
        scheduler.advance(by: .seconds(3))
        #expect(dismissed == [first])
    }

    @Test func aHoveredAlertStaysUp() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        scheduler.advance(by: .seconds(5))
        timers.hoverBegan(first)
        scheduler.advance(by: .seconds(60))
        #expect(dismissed.isEmpty)
    }

    @Test func theTimerRestartsInFullWhenTheHoverEnds() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        scheduler.advance(by: .seconds(5))
        timers.hoverBegan(first)
        scheduler.advance(by: .seconds(20))
        timers.hoverEnded(first)
        scheduler.advance(by: .milliseconds(7_999))
        #expect(dismissed.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(dismissed == [first])
    }

    @Test func anAlertGoneFromTheStoreIsNotDismissedAgain() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first, second])
        timers.show([second])
        scheduler.advance(by: .seconds(8))
        #expect(dismissed == [second])
    }

    @Test func hoverEndingAfterTheAlertIsGoneStartsNoTimer() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        timers.hoverBegan(first)
        timers.show([])
        timers.hoverEnded(first)
        scheduler.advance(by: .seconds(8))
        #expect(dismissed.isEmpty)
    }

    @Test func showingAgainWhileHoveredStartsNoTimer() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        timers.hoverBegan(first)
        timers.show([first, second])
        scheduler.advance(by: .seconds(8))
        #expect(dismissed == [second])
    }

    @Test func aCardTakenOffScreenWhileHoveredGetsAFreshTimerWhenBack() {
        var dismissed: [UUID] = []
        let timers = makeTimers { dismissed.append($0) }
        timers.show([first])
        timers.hoverBegan(first)
        timers.show([])
        timers.hoverEnded(first)
        scheduler.advance(by: .seconds(30))
        #expect(dismissed.isEmpty)
        timers.show([first])
        scheduler.advance(by: .seconds(8))
        #expect(dismissed == [first])
    }
}
