import Foundation

extension PanelController {
    /// The panel's times: clock times ("16:02"), running timers ("3:12") and turn durations ("33s").
    struct TimeText {
        var timeZone: TimeZone = .current

        func clock(_ date: Date) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return "\(parts.hour ?? 0):\(twoDigits(parts.minute ?? 0))"
        }

        func timer(from start: Date, to now: Date) -> String {
            let elapsed = max(0, Int(now.timeIntervalSince(start)))
            let (hours, minutes, seconds) = (elapsed / 3600, elapsed / 60 % 60, elapsed % 60)
            return hours > 0 ? "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))" : "\(minutes):\(twoDigits(seconds))"
        }

        func duration(_ duration: Duration) -> String {
            let total = max(0, Int(duration.components.seconds))
            let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m \(seconds)s" }
            return "\(seconds)s"
        }

        private func twoDigits(_ value: Int) -> String {
            value < 10 ? "0\(value)" : "\(value)"
        }
    }
}
