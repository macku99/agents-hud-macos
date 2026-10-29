/// Everything the HUD asks of herdr. Every call names the machine it goes to.
public protocol HerdrClient: Sendable {
    func agents(on machine: MachineID) async throws(HerdrError) -> [AgentInfo]
    func agent(_ pane: PaneID, on machine: MachineID) async throws(HerdrError) -> AgentInfo
    /// Recent screen text of the pane, plain text without ANSI escapes.
    func read(_ pane: PaneID, source: ReadSource, lines: Int, on machine: MachineID) async throws(HerdrError) -> String
    /// Focuses the pane in herdr, which also marks it seen there.
    func focus(_ pane: PaneID, on machine: MachineID) async throws(HerdrError)
    /// Sends `text` only if the pane still hosts `identity` and is ready for input, checked right
    /// before writing. Never retries; an unconfirmed write comes back as `.uncertain`.
    func send(_ text: String, to identity: AgentIdentity) async -> PromptOutcome
    /// Status changes pushed by herdr. The stream ends (or throws) when the connection drops;
    /// callers reconcile with `agents(on:)` and subscribe again.
    func events(on machine: MachineID) -> AsyncThrowingStream<HerdrEvent, any Error>
}
