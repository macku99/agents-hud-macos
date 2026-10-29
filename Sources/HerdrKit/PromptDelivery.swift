import Foundation

/// The checked send behind `LiveHerdrClient.send`. Everything up to the moment the kernel accepts the
/// first byte of the prompt request is a refusal, since nothing reached herdr. Any failure after that
/// is uncertain, including every error reply except the codes in `preInputRejections`.
enum PromptDelivery {
    static let maximumBytes = 60_000

    /// herdr 0.9.5's socket API docs (socket-api.mdx, line 114) say that for an already blocked agent
    /// `agent.prompt` "returns `agent_blocked` without sending input". No other error code is documented
    /// as raised before input reaches the pane, and `agent.prompt` runs asynchronously in herdr, so
    /// every other error reply is treated as uncertain.
    static let preInputRejections: Set = ["agent_blocked"]

    static func invalidTextReason(_ text: String) -> String? {
        if text.isEmpty { return "the prompt is empty" }
        if text.utf8.count > maximumBytes { return "the prompt is longer than \(maximumBytes) bytes" }
        if text.utf8.contains(0) { return "the prompt contains a NUL character" }
        return nil
    }

    /// Why the pane can no longer take this prompt, or nil when it still hosts `identity` and is ready.
    static func recheck(_ identity: AgentIdentity, over connection: HerdrConnection) throws(HerdrError) -> RefusalReason? {
        let reply = try connection.call("agent.get", HerdrParams.Target(target: identity.paneID.rawValue))
        let current = try HerdrConnection.decoding { try AgentInfo.decodeGet(reply, machine: identity.machine) }
        guard current.identity == identity else { return .agentChanged }
        guard current.status == .idle || current.status == .done else { return .notReady(current.status) }
        return nil
    }

    /// Writes the prompt request and reads its acknowledgement.
    static func submit(_ text: String, to identity: AgentIdentity, over connection: HerdrConnection) -> PromptOutcome {
        let writtenBefore = connection.socket.bytesWritten
        let pending: HerdrConnection.PendingReply
        do {
            pending = try connection.send("agent.prompt", HerdrParams.Prompt(target: identity.paneID.rawValue, text: text))
        } catch {
            guard connection.socket.bytesWritten > writtenBefore else { return .refused(error.refusal) }
            return .uncertain(error.summary)
        }

        let ack: Data
        do {
            ack = try connection.reply(to: pending)
        } catch .rejected(let code, let message) where preInputRejections.contains(code) {
            return .refused(.rejected("\(code): \(message)"))
        } catch {
            return .uncertain(error.summary)
        }
        guard let confirmed = try? JSONDecoder().decode(Ack.self, from: ack).result, confirmed.type == "agent_prompted" else {
            return .uncertain("herdr did not confirm the prompt")
        }
        guard let terminal = confirmed.agent?.terminal_id else {
            return .uncertain("herdr did not confirm which terminal got the prompt")
        }
        guard terminal == identity.terminalID else {
            return .uncertain("herdr confirmed the prompt for a different terminal")
        }
        return .delivered
    }

    private struct Ack: Decodable {
        struct Result: Decodable {
            struct Agent: Decodable { let terminal_id: String? }
            let type: String
            let agent: Agent?
        }
        let result: Result
    }
}

extension HerdrError {
    /// A short description for refusals and uncertain outcomes shown to the user.
    var summary: String {
        switch self {
        case .notInstalled: "herdr is not installed"
        case .unreachable(let detail): detail
        case .timedOut: "herdr did not answer in time"
        case .outputTooLarge: "herdr's reply was too large"
        case .unexpectedResponse(let detail): "unexpected reply from herdr: \(detail)"
        case .rejected(let code, let message): "\(code): \(message)"
        }
    }

    /// The refusal for an error that happened before anything was written.
    var refusal: RefusalReason {
        if case .rejected = self { return .rejected(summary) }
        return .unreachable(summary)
    }
}
