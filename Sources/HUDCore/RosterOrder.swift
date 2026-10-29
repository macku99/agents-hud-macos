/// The roster's order: agents needing attention, then working ones, then the rest. Within a group
/// herdr's order is kept.
enum RosterOrder {
    static func sorted(_ entries: [RosterEntry]) -> [RosterEntry] {
        entries.enumerated()
            .sorted { (group(of: $0.element), $0.offset) < (group(of: $1.element), $1.offset) }
            .map(\.element)
    }

    private static func group(of entry: RosterEntry) -> Int {
        if entry.attention != .none { return 0 }
        return entry.agent.status == .working ? 1 : 2
    }
}
