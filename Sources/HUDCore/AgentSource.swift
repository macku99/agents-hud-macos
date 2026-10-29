import HerdrKit

/// Something that knows a set of agents and reports them as whole snapshots: herdr on one machine,
/// or one Claude Desktop instance. The store merges every source's latest snapshot into one roster.
@MainActor
public protocol AgentSource: AnyObject, Sendable {
    var id: SourceID { get }
    /// Names the source where the HUD speaks about it as a whole, such as "herdr".
    var label: String { get }
    /// Starts the source: loads the first roster, then publishes every later one until `stop()`, which
    /// ends the stream. The first element is the first roster, published only once the source would
    /// notice any change after it. Calling it again restarts the source and ends the earlier stream.
    func snapshots() -> AsyncStream<SourceSnapshot>
    func stop()
    /// Reads the whole roster again now. Returns the snapshot it also publishes, or `nil` when the
    /// source was stopped or restarted before the read finished.
    func refresh() async -> SourceSnapshot?
}

public struct SourceID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// One agent across every source: the source plus the source's own id for it (a herdr pane, a session).
public struct AgentKey: Hashable, Sendable, CustomStringConvertible {
    public let source: SourceID
    public let id: String

    public init(source: SourceID, id: String) {
        self.source = source
        self.id = id
    }

    public var description: String { "\(source)/\(id)" }
}

/// Tells one agent from the next under the same key, such as a new agent in a reused herdr pane.
/// Wraps any Sendable value, so a source can use its own notion of identity.
public struct AgentIncarnation: Hashable, @unchecked Sendable {
    private let value: AnyHashable

    public init<Value: Hashable & Sendable>(_ value: Value) {
        self.value = AnyHashable(value)
    }
}

public enum SourceState: Hashable, Sendable {
    case connecting
    case connected
    /// The source cannot be read; the reason is said in plain words.
    case unavailable(String)
}

public struct SourceSnapshot: Hashable, Sendable {
    /// Rises with every snapshot a source publishes, so an older one arriving late can be dropped.
    public let revision: UInt64
    public let state: SourceState
    /// When the source cannot be read, the agents it last reported, or none if it never could.
    public let agents: [AgentSnapshot]
    /// True when `agents` comes from reading the whole roster, false when only one agent was re-read.
    public let isFullListing: Bool

    public init(revision: UInt64, state: SourceState, agents: [AgentSnapshot], isFullListing: Bool) {
        self.revision = revision
        self.state = state
        self.agents = agents
        self.isFullListing = isFullListing
    }
}

/// One agent as its source reports it, in the terms the HUD shows.
public struct AgentSnapshot: Hashable, Sendable {
    public let key: AgentKey
    public let incarnation: AgentIncarnation
    public let title: String
    public let status: AgentStatus
    /// Where the agent runs, shown first in its row: herdr's workspace, or the Desktop instance.
    public let place: String?
    /// The kind of agent, such as `claude`.
    public let kind: String
    public let cwd: String?
    public let transcript: AgentSessionRef?
    public let completion: CompletionToken
    /// Present only on agents running in herdr, which alone take prompts, focus and screen reads.
    public let herdr: HerdrHandle?

    public init(key: AgentKey, incarnation: AgentIncarnation, title: String, status: AgentStatus, place: String?,
                kind: String, cwd: String?, transcript: AgentSessionRef?, completion: CompletionToken, herdr: HerdrHandle?) {
        self.key = key
        self.incarnation = incarnation
        self.title = title
        self.status = status
        self.place = place
        self.kind = kind
        self.cwd = cwd
        self.transcript = transcript
        self.completion = completion
        self.herdr = herdr
    }
}

/// What herdr needs to act on an agent it hosts.
public struct HerdrHandle: Hashable, Sendable {
    public let identity: AgentIdentity
    /// herdr's counter for the agent's current state; a screen read is repeated when it changes.
    public let stateChangeSeq: UInt64

    public init(identity: AgentIdentity, stateChangeSeq: UInt64) {
        self.identity = identity
        self.stateChangeSeq = stateChangeSeq
    }

    public var paneID: PaneID { identity.paneID }
}

/// Which finished turn an agent is on, as a named counter and its value. Two counters are unrelated,
/// so a token from another counter counts as a new finish.
public struct CompletionToken: Hashable, Sendable {
    public let counter: String
    public let sequence: UInt64

    public init(counter: String, sequence: UInt64) {
        self.counter = counter
        self.sequence = sequence
    }

    func isNewer(than viewed: CompletionToken?) -> Bool {
        guard let viewed, viewed.counter == counter else { return true }
        return sequence > viewed.sequence
    }
}
