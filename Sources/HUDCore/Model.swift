import Foundation
import HerdrKit

public enum Attention: Hashable, Sendable {
    case none
    /// Finished a turn the user has not viewed in the panel (nor, for a herdr agent, focused in herdr).
    case unseen
    case blocked
}

public struct RosterEntry: Hashable, Sendable, Identifiable {
    public let agent: AgentSnapshot
    public let attention: Attention
    /// When the HUD first saw the agent in its current status (herdr reports no timestamps). Rows show
    /// it as a running timer while working and as a clock time otherwise.
    public let stateSince: Date?

    public init(agent: AgentSnapshot, attention: Attention, stateSince: Date?) {
        self.agent = agent
        self.attention = attention
        self.stateSince = stateSince
    }

    public var id: AgentKey { agent.key }
}

/// Where the prompt box of one agent stands. Whether the agent itself can take a prompt (blocked,
/// working) comes from its status, not from this.
public enum SendState: Hashable, Sendable {
    case ready
    case sending
    /// The last send may have arrived; sending stays blocked until the user reconciles.
    case uncertain(String)
    /// Nothing was sent. Clears back to `.ready` when the draft changes or the agent is selected again.
    case refused(RefusalReason)
}

/// How the HUD's link to one source stands, so an empty roster can be told apart from a missing source.
public struct SourceConnection: Hashable, Sendable, Identifiable {
    public let id: SourceID
    public let label: String
    public internal(set) var state: SourceState

    public init(id: SourceID, label: String, state: SourceState) {
        self.id = id
        self.label = label
        self.state = state
    }
}

public struct HUDAlert: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case finished, needsInput }

    public let id: UUID
    public let key: AgentKey
    public let kind: Kind
    public let title: String
    public let preview: String
    public let at: Date

    public init(id: UUID = UUID(), key: AgentKey, kind: Kind, title: String, preview: String, at: Date) {
        self.id = id
        self.key = key
        self.kind = kind
        self.title = title
        self.preview = preview
        self.at = at
    }
}
