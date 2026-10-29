import Foundation

extension OverlayController {
    /// Dismisses each alert 8 s after it shows. Hovering holds it; the full 8 s start again when the
    /// hover ends.
    @MainActor
    final class AlertTimers {
        @MainActor
        protocol Scheduler: AnyObject {
            func run(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Cancel
        }

        struct Cancel {
            let cancel: @MainActor () -> Void
        }

        /// Runs actions on the main actor after a real-time delay.
        final class TaskScheduler: Scheduler {
            func run(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Cancel {
                let task = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    action()
                }
                return Cancel { task.cancel() }
            }
        }

        static let delay: Duration = .seconds(8)

        private let scheduler: any Scheduler
        private let dismiss: @MainActor (UUID) -> Void
        private var shown: Set<UUID> = []
        private var hovered: Set<UUID> = []
        private var running: [UUID: Cancel] = [:]

        init(scheduler: any Scheduler, dismiss: @escaping @MainActor (UUID) -> Void) {
            self.scheduler = scheduler
            self.dismiss = dismiss
        }

        /// The alerts on screen now; new ones start their timer, gone ones lose it.
        func show(_ ids: [UUID]) {
            let current = Set(ids)
            for gone in shown.subtracting(current) {
                stop(gone)
                hovered.remove(gone)
            }
            for new in current.subtracting(shown) {
                start(new)
            }
            shown = current
        }

        func hoverBegan(_ id: UUID) {
            guard shown.contains(id) else { return }
            hovered.insert(id)
            stop(id)
        }

        func hoverEnded(_ id: UUID) {
            guard hovered.remove(id) != nil, shown.contains(id) else { return }
            start(id)
        }

        private func start(_ id: UUID) {
            running[id] = scheduler.run(after: Self.delay) { [weak self] in
                self?.running[id] = nil
                self?.dismiss(id)
            }
        }

        private func stop(_ id: UUID) {
            running.removeValue(forKey: id)?.cancel()
        }
    }
}
