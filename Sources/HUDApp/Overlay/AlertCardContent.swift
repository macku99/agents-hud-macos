import Foundation
import HerdrKit
import HUDCore

extension OverlayController {
    /// What one alert card shows.
    struct AlertCardContent: Hashable, Identifiable {
        let id: UUID
        let key: AgentKey
        let kind: HUDAlert.Kind
        let title: String
        let meta: String
        let preview: String?

        /// Newest first, the order the stack places them outward from H.
        static func cards(for alerts: [HUDAlert], roster: [RosterEntry], timeZone: TimeZone = .current) -> [Self] {
            alerts.sorted { $0.at > $1.at }.map { alert in
                let cwd = roster.first { $0.id == alert.key }?.agent.cwd
                let preview = alert.preview.trimmingCharacters(in: .whitespacesAndNewlines)
                return Self(id: alert.id, key: alert.key, kind: alert.kind, title: alert.title,
                            meta: OverlayText.alertMeta(kind: alert.kind, project: OverlayText.project(cwd: cwd),
                                                        at: alert.at, timeZone: timeZone),
                            preview: preview.isEmpty ? nil : preview)
            }
        }
    }
}
