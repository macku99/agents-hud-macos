import Foundation
import Testing
@testable import HerdrKit

// Shaped like `herdr agent list` output (herdr 0.9.5, protocol 22); values are synthetic.
private let agentListJSON = Data("""
{"id":"cli:agent:list","result":{"agents":[
 {"agent":"claude","agent_status":"done","completion_seq":19,"cwd":"/Users/me/project",
  "focused":false,"pane_id":"w8:p1","revision":4,"state_change_seq":21,"tab_id":"w8:t1",
  "terminal_id":"term_aaa","terminal_title":"✳ Fix the sync","terminal_title_stripped":"Fix the sync",
  "workspace_id":"w8",
  "agent_session":{"agent":"claude","kind":"path","source":"herdr:claude","value":"/Users/me/.claude-work/projects/x/abc.jsonl"}},
 {"agent":"claude","agent_status":"working","cwd":"/Users/me/other","focused":true,"pane_id":"w1:p1",
  "revision":6,"state_change_seq":103,"tab_id":"w1:t1","terminal_id":"term_bbb",
  "terminal_title":"◑ Sidebar","terminal_title_stripped":"Sidebar","workspace_id":"w1"}
],"type":"agent_list"}}
""".utf8)

@Test func decodesEveryAgentInAListResponse() throws {
    let agents = try AgentInfo.decodeList(agentListJSON, machine: .local)
    #expect(agents.map(\.paneID) == [PaneID("w8:p1"), PaneID("w1:p1")])
}

@Test func decodesStatusTitleAndSequencesOfAFinishedAgent() throws {
    let done = try AgentInfo.decodeList(agentListJSON, machine: .local)[0]
    #expect(done.status == .done)
    #expect(done.title == "Fix the sync")
    #expect(done.completionSeq == 19)
    #expect(done.stateChangeSeq == 21)
    #expect(done.cwd == "/Users/me/project")
}

@Test func decodesTheTranscriptPathSessionReference() throws {
    let done = try AgentInfo.decodeList(agentListJSON, machine: .local)[0]
    #expect(done.session == AgentSessionRef(kind: .path, value: "/Users/me/.claude-work/projects/x/abc.jsonl"))
}

@Test func missingOptionalFieldsDecodeAsNil() throws {
    let working = try AgentInfo.decodeList(agentListJSON, machine: .local)[1]
    #expect(working.completionSeq == nil)
    #expect(working.session == nil)
}

@Test func identityCarriesMachineAndEveryIdentifyingField() throws {
    let done = try AgentInfo.decodeList(agentListJSON, machine: .local)[0]
    #expect(done.identity == AgentIdentity(
        machine: .local, paneID: PaneID("w8:p1"), terminalID: "term_aaa",
        workspaceID: "w8", agent: "claude",
        session: AgentSessionRef(kind: .path, value: "/Users/me/.claude-work/projects/x/abc.jsonl")))
}

@Test func unknownStatusValueDecodesAsUnknown() throws {
    let json = Data("""
    {"result":{"agents":[{"agent":"claude","agent_status":"napping","pane_id":"w2:p1",
      "terminal_id":"t","workspace_id":"w2","tab_id":"w2:t1","state_change_seq":1}]}}
    """.utf8)
    #expect(try AgentInfo.decodeList(json, machine: .local)[0].status == .unknown)
}

@Test func decodesTheAgentOfAGetResponse() throws {
    let json = Data("""
    {"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_status":"idle","pane_id":"w1:p1",
      "terminal_id":"term_bbb","workspace_id":"w1","tab_id":"w1:t1","state_change_seq":104,
      "completion_seq":104},"type":"agent_info"}}
    """.utf8)
    let agent = try AgentInfo.decodeGet(json, machine: .local)
    #expect(agent.status == .idle)
    #expect(agent.completionSeq == 104)
}

@Test func malformedResponseThrowsUnexpectedResponse() {
    let error = #expect(throws: HerdrError.self) {
        try AgentInfo.decodeList(Data("{\"result\":{}}".utf8), machine: .local)
    }
    guard case .unexpectedResponse = error else {
        Issue.record("expected .unexpectedResponse, got \(String(describing: error))")
        return
    }
}

@Test func oneMalformedAgentFailsTheWholeList() {
    let json = Data("""
    {"result":{"agents":[
      {"agent":"claude","agent_status":"idle","pane_id":"w1:p1","terminal_id":"t1","workspace_id":"w1","tab_id":"w1:t1"},
      {"agent":"claude","agent_status":"idle","pane_id":"w2:p1","workspace_id":"w2","tab_id":"w2:t1"}]}}
    """.utf8)
    #expect(throws: HerdrError.self) { try AgentInfo.decodeList(json, machine: .local) }
}

private func singleAgent(_ fields: String) throws -> AgentInfo {
    let json = Data("""
    {"result":{"agents":[{"agent":"claude","agent_status":"idle","pane_id":"w5:p1","terminal_id":"t5",
      "workspace_id":"w5","tab_id":"w5:t1"\(fields)}]}}
    """.utf8)
    return try AgentInfo.decodeList(json, machine: .local)[0]
}

@Test func titlePrefersTheAgentNameOverTheTerminalTitle() throws {
    #expect(try singleAgent(#","name":"reviewer","terminal_title_stripped":"Fix it""#).title == "reviewer")
}

@Test func titleFallsBackToTheStrippedTerminalTitle() throws {
    #expect(try singleAgent(#","terminal_title_stripped":"Fix it""#).title == "Fix it")
}

@Test func titleFallsBackToThePaneIDWhenNothingElseIsKnown() throws {
    #expect(try singleAgent("").title == "w5:p1")
}

@Test func missingStateChangeSeqDecodesAsZero() throws {
    #expect(try singleAgent("").stateChangeSeq == 0)
}

@Test func explicitNullsDecodeAsNil() throws {
    let agent = try singleAgent(#","cwd":null,"completion_seq":null,"agent_session":null,"name":null"#)
    #expect(agent.cwd == nil)
    #expect(agent.completionSeq == nil)
    #expect(agent.session == nil)
}

@Test func unknownSessionKindDecodesAsNoSession() throws {
    let agent = try singleAgent(#","agent_session":{"agent":"claude","kind":"url","source":"x","value":"y"}"#)
    #expect(agent.session == nil)
}

@Test func nullAgentKindFallsBackToTheDisplayAgent() throws {
    let json = Data("""
    {"result":{"agents":[{"agent":null,"display_agent":"Claude","agent_status":"idle","pane_id":"w6:p1",
      "terminal_id":"t6","workspace_id":"w6","tab_id":"w6:t1"}]}}
    """.utf8)
    #expect(try AgentInfo.decodeList(json, machine: .local)[0].agent == "Claude")
}

@Test func agentWithNoKindAtAllDecodesAsUnknown() throws {
    let json = Data("""
    {"result":{"agents":[{"agent_status":"idle","pane_id":"w6:p1","terminal_id":"t6","workspace_id":"w6","tab_id":"w6:t1"}]}}
    """.utf8)
    #expect(try AgentInfo.decodeList(json, machine: .local)[0].agent == "unknown")
}
