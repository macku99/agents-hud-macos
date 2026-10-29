import Foundation

/// The herdr server a call goes to. v1 only talks to the local one; every call still takes it
/// so remote machines (`herdr --machine <label>`) can be added without reshaping the API.
public enum MachineID: Hashable, Sendable {
    case local
}

/// herdr's pane id, such as `w1:p1`. Unique only within one herdr server.
public struct PaneID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public enum AgentStatus: String, Hashable, Sendable {
    case idle, working, blocked, done, unknown
}

/// Where herdr says an agent's own session lives: a Claude Code session id or its transcript path.
public struct AgentSessionRef: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case id, path }
    public let kind: Kind
    public let value: String
    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

/// Everything that must be unchanged for a prompt to reach the agent the user picked.
public struct AgentIdentity: Hashable, Sendable {
    public let machine: MachineID
    public let paneID: PaneID
    public let terminalID: String
    public let workspaceID: String
    public let agent: String
    public let session: AgentSessionRef?

    public init(machine: MachineID, paneID: PaneID, terminalID: String, workspaceID: String, agent: String, session: AgentSessionRef?) {
        self.machine = machine
        self.paneID = paneID
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.agent = agent
        self.session = session
    }
}

/// One agent as herdr reports it.
public struct AgentInfo: Hashable, Sendable {
    public let machine: MachineID
    public let paneID: PaneID
    public let terminalID: String
    public let workspaceID: String
    public let tabID: String
    public let agent: String
    public let status: AgentStatus
    public let title: String
    public let cwd: String?
    /// Identifies the idle transition that completed work, whether or not anyone has seen it.
    public let completionSeq: UInt64?
    public let stateChangeSeq: UInt64
    public let session: AgentSessionRef?

    public init(machine: MachineID, paneID: PaneID, terminalID: String, workspaceID: String, tabID: String, agent: String,
                status: AgentStatus, title: String, cwd: String?, completionSeq: UInt64?, stateChangeSeq: UInt64,
                session: AgentSessionRef?) {
        self.machine = machine
        self.paneID = paneID
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.agent = agent
        self.status = status
        self.title = title
        self.cwd = cwd
        self.completionSeq = completionSeq
        self.stateChangeSeq = stateChangeSeq
        self.session = session
    }

    public var identity: AgentIdentity {
        AgentIdentity(machine: machine, paneID: paneID, terminalID: terminalID, workspaceID: workspaceID, agent: agent, session: session)
    }
}

public enum ReadSource: String, Sendable {
    case visible
    case recentUnwrapped = "recent_unwrapped"
}

public enum RefusalReason: Hashable, Sendable {
    /// The pane now hosts a different agent, terminal or session than the one selected.
    case agentChanged
    case notReady(AgentStatus)
    case invalidText(String)
    /// herdr could not be reached; nothing was written.
    case unreachable(String)
    /// herdr refused before any input reached the pane (for example `agent_blocked`).
    case rejected(String)
}

/// The result of a send. Only `.uncertain` means the text may have reached the agent without confirmation.
public enum PromptOutcome: Hashable, Sendable {
    case delivered
    case refused(RefusalReason)
    case uncertain(String)
}

/// What the HUD needs from herdr's event subscription. Anything else herdr pushes (agents appearing,
/// panes closing) is handled inside the transport by reconciling with `agents(on:)`.
public enum HerdrEvent: Hashable, Sendable {
    case agentStatusChanged(PaneID, AgentStatus)
}

public enum HerdrError: Error, Hashable, Sendable {
    case notInstalled
    case unreachable(String)
    case timedOut
    case outputTooLarge
    case unexpectedResponse(String)
    case rejected(code: String, message: String)
}

// MARK: - Wire decoding

extension AgentInfo {
    /// Decodes the `result.agents` array of an `agent list` response. One malformed agent fails the
    /// whole list: an error surfaces a herdr change, where silently dropping agents would hide it.
    public static func decodeList(_ data: Data, machine: MachineID) throws -> [AgentInfo] {
        let envelope = try decode(ListEnvelope.self, from: data)
        return envelope.result.agents.map { $0.agentInfo(machine: machine) }
    }

    /// Decodes the `result.agent` object of an `agent get` response.
    public static func decodeGet(_ data: Data, machine: MachineID) throws -> AgentInfo {
        try decode(GetEnvelope.self, from: data).result.agent.agentInfo(machine: machine)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HerdrError.unexpectedResponse(String(describing: error))
        }
    }
}

private struct ListEnvelope: Decodable {
    struct Result: Decodable { let agents: [WireAgent] }
    let result: Result
}

private struct GetEnvelope: Decodable {
    struct Result: Decodable { let agent: WireAgent }
    let result: Result
}

private struct WireAgent: Decodable {
    struct Session: Decodable {
        let kind: String
        let value: String
    }

    let pane_id: String
    let terminal_id: String
    let workspace_id: String
    let tab_id: String
    /// herdr reports null when it cannot name the agent kind; `display_agent` may still be set.
    let agent: String?
    let display_agent: String?
    let agent_status: String
    let terminal_title_stripped: String?
    let name: String?
    let cwd: String?
    let completion_seq: UInt64?
    let state_change_seq: UInt64?
    let agent_session: Session?

    func agentInfo(machine: MachineID) -> AgentInfo {
        AgentInfo(
            machine: machine,
            paneID: PaneID(pane_id),
            terminalID: terminal_id,
            workspaceID: workspace_id,
            tabID: tab_id,
            agent: agent ?? display_agent ?? "unknown",
            status: AgentStatus(rawValue: agent_status) ?? .unknown,
            title: name ?? terminal_title_stripped ?? pane_id,
            cwd: cwd,
            completionSeq: completion_seq,
            stateChangeSeq: state_change_seq ?? 0,
            session: agent_session.flatMap { session in
                AgentSessionRef.Kind(rawValue: session.kind).map { AgentSessionRef(kind: $0, value: session.value) }
            }
        )
    }
}
