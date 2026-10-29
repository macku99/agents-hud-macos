import Testing
import HerdrKit
import HerdrKitTesting

@Test func agentsReturnsTheCurrentSnapshot() async throws {
    let fake = FakeHerdr()
    let agent = AgentInfo.fake(pane: "w1:p1", status: .working)
    fake.setAgents([agent])
    #expect(try await fake.agents(on: .local) == [agent])
}

@Test func aScriptedListFailureIsThrownOnceThenTheSnapshotReturns() async throws {
    let fake = FakeHerdr()
    fake.setAgents([AgentInfo.fake(pane: "w1:p1")])
    fake.failNext(.agents, with: .timedOut)
    await #expect(throws: HerdrError.timedOut) { try await fake.agents(on: .local) }
    #expect(try await fake.agents(on: .local).count == 1)
}

@Test func agentReturnsTheMatchingPane() async throws {
    let fake = FakeHerdr()
    fake.setAgents([AgentInfo.fake(pane: "w1:p1"), AgentInfo.fake(pane: "w2:p1", status: .done)])
    #expect(try await fake.agent(PaneID("w2:p1"), on: .local).status == .done)
}

@Test func agentForAnUnknownPaneIsRejected() async {
    let fake = FakeHerdr()
    await #expect(throws: HerdrError.rejected(code: "agent_not_found", message: "w9:p1")) {
        try await fake.agent(PaneID("w9:p1"), on: .local)
    }
}

@Test func aScriptedAgentFailureIsThrownForAKnownPane() async {
    let fake = FakeHerdr()
    fake.setAgents([AgentInfo.fake(pane: "w1:p1")])
    fake.failNext(.agent, with: .unreachable("socket gone"))
    await #expect(throws: HerdrError.unreachable("socket gone")) { try await fake.agent(PaneID("w1:p1"), on: .local) }
}

@Test func aScriptedReadFailureIsThrown() async {
    let fake = FakeHerdr()
    fake.failNext(.read, with: .outputTooLarge)
    await #expect(throws: HerdrError.outputTooLarge) {
        try await fake.read(PaneID("w1:p1"), source: .visible, lines: 20, on: .local)
    }
}

@Test func aScriptedFocusFailureIsThrown() async {
    let fake = FakeHerdr()
    fake.failNext(.focus, with: .notInstalled)
    await #expect(throws: HerdrError.notInstalled) { try await fake.focus(PaneID("w1:p1"), on: .local) }
}

@Test func sendReturnsScriptedOutcomesInOrder() async {
    let fake = FakeHerdr()
    fake.scriptSend(.delivered, .uncertain("timeout"))
    let identity = AgentInfo.fake(pane: "w1:p1").identity
    #expect(await fake.send("one", to: identity) == .delivered)
    #expect(await fake.send("two", to: identity) == .uncertain("timeout"))
}

@Test func anUnscriptedSendIsUncertain() async {
    let fake = FakeHerdr()
    let outcome = await fake.send("hi", to: AgentInfo.fake(pane: "w1:p1").identity)
    #expect(outcome == .uncertain("FakeHerdr: no send outcome scripted"))
}

@Test func aHeldSendStaysInFlightUntilReleased() async {
    let fake = FakeHerdr()
    fake.holdSends()
    fake.scriptSend(.delivered)
    let identity = AgentInfo.fake(pane: "w1:p1").identity
    let pending = Task { await fake.send("slow", to: identity) }
    await fake.waitForSendsInFlight(1)
    #expect(fake.sendsInFlight == 1)
    fake.releaseSends()
    #expect(await pending.value == .delivered)
    #expect(fake.sendsInFlight == 0)
}

@Test func callsAreRecordedInOrder() async throws {
    let fake = FakeHerdr()
    let agent = AgentInfo.fake(pane: "w1:p1")
    fake.setAgents([agent])
    fake.scriptSend(.delivered)
    _ = try await fake.agents(on: .local)
    _ = fake.events(on: .local)
    _ = await fake.send("hello", to: agent.identity)
    try await fake.focus(PaneID("w1:p1"), on: .local)
    #expect(fake.calls == [.agents, .events, .send("hello", agent.identity), .focus(PaneID("w1:p1"))])
}

@Test func readReturnsTheScreenTextSetForThePane() async throws {
    let fake = FakeHerdr()
    fake.setScreen("⏺ done", for: PaneID("w1:p1"))
    #expect(try await fake.read(PaneID("w1:p1"), source: .recentUnwrapped, lines: 180, on: .local) == "⏺ done")
}

@Test func emittedEventsReachTheSubscriber() async throws {
    let fake = FakeHerdr()
    let stream = fake.events(on: .local)
    fake.emit(.agentStatusChanged(PaneID("w1:p1"), .done))
    fake.finishEvents()
    var received: [HerdrEvent] = []
    for try await event in stream { received.append(event) }
    #expect(received == [.agentStatusChanged(PaneID("w1:p1"), .done)])
}

@Test func resubscribingAfterTheStreamEndsReceivesNewEvents() async throws {
    let fake = FakeHerdr()
    let first = fake.events(on: .local)
    fake.finishEvents(throwing: HerdrError.unreachable("dropped"))
    await #expect(throws: HerdrError.unreachable("dropped")) { for try await _ in first {} }

    let second = fake.events(on: .local)
    fake.emit(.agentStatusChanged(PaneID("w1:p1"), .working))
    fake.finishEvents()
    var received: [HerdrEvent] = []
    for try await event in second { received.append(event) }
    #expect(received == [.agentStatusChanged(PaneID("w1:p1"), .working)])
}

@Test func fakeAgentDefaultsToAnIdleClaudeAgentWithMatchingIds() {
    let agent = AgentInfo.fake(pane: "w3:p2")
    #expect(agent.status == .idle)
    #expect(agent.agent == "claude")
    #expect(agent.workspaceID == "w3")
    #expect(agent.tabID == "w3:t1")
    #expect(agent.terminalID == "term-w3:p2")
}

@Test func fakeAgentTakesCwdAndAgentKind() {
    let agent = AgentInfo.fake(pane: "w3:p2", agent: "codex", cwd: "/tmp/project")
    #expect(agent.agent == "codex")
    #expect(agent.cwd == "/tmp/project")
}
