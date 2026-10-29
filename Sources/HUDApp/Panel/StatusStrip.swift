import HUDCore

extension PanelController {
    /// The one line under the header: which machine, how many agents, how many need M, and any
    /// source still connecting or out of reach.
    struct StatusStrip: Equatable {
        let text: String
        /// False when a source cannot be reached, so the strip's dot stops showing the accent.
        let isAvailable: Bool

        init(roster: [RosterEntry], connections: [SourceConnection]) {
            var parts: [String] = []
            if connections.contains(where: { $0.state == .connected }) {
                let attention = roster.count { $0.attention != .none }
                parts.append("\(roster.count) \(roster.count == 1 ? "agent" : "agents") · "
                    + "\(attention) \(attention == 1 ? "needs" : "need") attention")
            }
            var unreachable = false
            for connection in connections {
                switch connection.state {
                case .connecting: parts.append("connecting to \(connection.label)")
                case .connected: break
                case .unavailable(let reason):
                    parts.append(reason)
                    unreachable = true
                }
            }
            text = (["this mac"] + parts).joined(separator: " · ")
            isAvailable = !unreachable
        }
    }
}
