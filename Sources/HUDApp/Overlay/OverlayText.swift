import Foundation
import HUDCore

extension OverlayController {
    /// The words and numbers H's badge and the alert cards show.
    enum OverlayText {
        static func badge(count: Int) -> String? {
            switch count {
            case ...0: nil
            case 1...9: String(count)
            default: "9+"
            }
        }

        static func project(cwd: String?) -> String? {
            cwd?.split(separator: "/").last.map(String.init)
        }

        static func alertMeta(kind: HUDAlert.Kind, project: String?, at date: Date, timeZone: TimeZone = .current) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let time = calendar.dateComponents([.hour, .minute], from: date)
            let clock = String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
            let state = switch kind {
            case .finished: "done"
            case .needsInput: "needs input"
            }
            return ([state, project, clock] as [String?]).compactMap(\.self).joined(separator: " · ")
        }
    }
}
