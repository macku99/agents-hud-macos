import HerdrKit
import HerdrKitTesting
import HUDCore

extension AgentSnapshot {
    /// A local herdr agent, as `AgentInfo.fake` describes it and herdr's source presents it.
    static func fake(pane: String, status: AgentStatus = .idle, title: String? = nil, agent: String = "claude",
                     cwd: String? = nil, completionSeq: UInt64? = nil, stateChangeSeq: UInt64 = 1,
                     session: AgentSessionRef? = nil) -> AgentSnapshot {
        HerdrAgentSource.snapshot(of: .fake(pane: pane, status: status, title: title, agent: agent, cwd: cwd,
                                            completionSeq: completionSeq, stateChangeSeq: stateChangeSeq, session: session),
                                  on: .local)
    }
}

extension AgentSnapshot {
    /// A Claude Desktop session of the Personal instance.
    static func desktop(_ session: String, status: AgentStatus = .done, transcript: AgentSessionRef? = nil) -> AgentSnapshot {
        AgentSnapshot(key: AgentKey(source: SourceID("desktop:personal"), id: session), incarnation: AgentIncarnation(session),
                      title: session, status: status, place: "Personal", kind: "claude", cwd: "/Users/m/Work/app",
                      transcript: transcript, completion: CompletionToken(counter: "idleSince", sequence: 1), herdr: nil)
    }
}

extension AgentKey {
    /// How the store names the local herdr's agent in `pane`.
    static func herdr(_ pane: String) -> AgentKey {
        AgentKey(source: HerdrAgentSource.id(for: .local), id: pane)
    }
}
