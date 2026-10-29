import Foundation
import HerdrKit
import HUDCore

extension PanelController {
    /// What one roster row says about an agent.
    struct RosterRow: Equatable {
        enum Marker: Equatable {
            /// Ochre square.
            case blocked
            /// Accent dot.
            case unseen
            /// Pulsing accent dot.
            case working
            /// Hollow faint ring.
            case settled
        }

        let title: String
        let meta: String
        let stateLine: String
        let marker: Marker

        init(_ entry: RosterEntry, now: Date, time: TimeText) {
            let agent = entry.agent
            title = agent.title
            meta = [agent.place, Self.project(agent.cwd), agent.kind].compactMap { $0 }.joined(separator: " · ")

            let state: String
            switch (agent.status, entry.attention) {
            case (.blocked, _), (_, .blocked):
                (marker, state) = (.blocked, "blocked · needs input")
            case (_, .unseen):
                (marker, state) = (.unseen, "done · unseen")
            case (.working, _):
                (marker, state) = (.working, "working")
            case (let status, .none):
                (marker, state) = (.settled, status.rawValue)
            }
            let stateTime = Self.since(entry, running: marker == .working, now: now, time: time)
            stateLine = [state, stateTime].compactMap { $0 }.joined(separator: " · ")
        }

        /// The detail title row's meta: `place · ~/path · kind · state time`.
        static func detailMeta(_ entry: RosterEntry, now: Date, time: TimeText, home: String) -> String {
            let agent = entry.agent
            let stateTime = since(entry, running: agent.status == .working, now: now, time: time)
            let state = [agent.status.rawValue, stateTime].compactMap { $0 }.joined(separator: " ")
            return [agent.place, path(agent.cwd, home: home), agent.kind, state].compactMap { $0 }
                .joined(separator: " · ")
        }

        /// A running timer for work in progress, otherwise the clock time the state began.
        private static func since(_ entry: RosterEntry, running: Bool, now: Date, time: TimeText) -> String? {
            guard let since = entry.stateSince else { return nil }
            return running ? time.timer(from: since, to: now) : time.clock(since)
        }

        private static func project(_ cwd: String?) -> String? {
            guard let cwd, !cwd.isEmpty else { return nil }
            return (cwd as NSString).lastPathComponent
        }

        private static func path(_ cwd: String?, home: String) -> String? {
            guard let cwd, !cwd.isEmpty else { return nil }
            if cwd == home { return "~" }
            if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
            return cwd
        }
    }
}
