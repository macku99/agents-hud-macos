import Foundation

/// One transcript line reduced to what Chat shows. Lines Chat has no use for don't parse.
struct TranscriptLine: Sendable, Equatable {
    enum Role: Sendable, Equatable { case user, assistant, system }

    enum Event: Sendable, Equatable {
        case prompt(String)
        /// A prompt typed while Claude was working, delivered into the turn still running.
        case queuedPrompt(String)
        case text(String)
        case toolUse(id: String, call: ToolCall)
        case toolResult(toolUseID: String, text: String?)
        case turnEnded(Duration)
    }

    let uuid: String
    let at: Date?
    let role: Role
    let events: [Event]

    /// Wrappers Claude Code writes into user entries for slash commands, shell-mode output and
    /// background-task notices; none of them is text the person typed.
    private static let wrapperTags = [
        "<command-name>", "<command-message>", "<command-args>", "<local-command-stdout>",
        "<local-command-stderr>", "<local-command-caveat>", "<task-notification>",
        "<bash-stdout>", "<bash-stderr>",
    ]
    private static let interruptionMarker = "[Request interrupted by user"
    /// What the person typed after `!` to run a shell command themselves.
    private static let shellInput = (open: "<bash-input>", close: "</bash-input>")

    init?(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uuid = json["uuid"] as? String,
              json["isSidechain"] as? Bool != true
        else { return nil }

        let role: Role
        let events: [Event]
        switch json["type"] as? String {
        case "user":
            role = .user
            events = Self.userEvents(json)
        case "assistant":
            role = .assistant
            events = Self.assistantEvents(json)
        case "attachment":
            role = .user
            events = Self.queuedPromptEvents(json)
        case "system":
            guard json["subtype"] as? String == "turn_duration",
                  let milliseconds = json["durationMs"] as? NSNumber
            else { return nil }
            role = .system
            events = [.turnEnded(.milliseconds(milliseconds.int64Value))]
        default:
            return nil
        }
        if role == .user && events.isEmpty { return nil }

        self.uuid = uuid
        self.at = (json["timestamp"] as? String).flatMap(Self.date)
        self.role = role
        self.events = events
    }

    private static func userEvents(_ json: [String: Any]) -> [Event] {
        guard json["isMeta"] as? Bool != true, json["isCompactSummary"] as? Bool != true else { return [] }
        let content = (json["message"] as? [String: Any])?["content"]
        if let text = content as? String {
            return prompt(text, origin: json["origin"]).map { [$0] } ?? []
        }
        guard let blocks = content as? [[String: Any]] else { return [] }
        var events: [Event] = blocks.compactMap { block in
            guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
            return .toolResult(toolUseID: id, text: resultText(block["content"]))
        }
        let typed = texts(of: blocks)
        if !typed.isEmpty, let prompt = prompt(typed.joined(separator: "\n"), origin: json["origin"]) {
            events.append(prompt)
        }
        return events
    }

    /// Prompts typed while Claude was working are recorded as attachments when Claude Code delivers them.
    private static func queuedPromptEvents(_ json: [String: Any]) -> [Event] {
        guard let attachment = json["attachment"] as? [String: Any],
              attachment["type"] as? String == "queued_command",
              attachment["commandMode"] as? String == "prompt"
        else { return [] }
        let text = attachment["prompt"] as? String
            ?? (attachment["prompt"] as? [[String: Any]]).map { texts(of: $0).joined(separator: "\n") }
        guard case .prompt(let typed) = text.flatMap({ prompt($0, origin: attachment["origin"]) }) else { return [] }
        return [.queuedPrompt(typed)]
    }

    private static func prompt(_ text: String, origin: Any?) -> Event? {
        if let kind = (origin as? [String: Any])?["kind"] as? String, kind != "human" { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(shellInput.open) && trimmed.hasSuffix(shellInput.close) {
            let command = trimmed.dropFirst(shellInput.open.count).dropLast(shellInput.close.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : .prompt("! " + command)
        }
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix(interruptionMarker),
              !wrapperTags.contains(where: trimmed.hasPrefix)
        else { return nil }
        return .prompt(trimmed)
    }

    private static func resultText(_ content: Any?) -> String? {
        if let text = content as? String { return ToolCall.shortenedResult(text) }
        guard let items = content as? [[String: Any]] else { return nil }
        return ToolCall.shortenedResult(texts(of: items).joined(separator: "\n"))
    }

    private static func texts(of blocks: [[String: Any]]) -> [String] {
        blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }

    private static func assistantEvents(_ json: [String: Any]) -> [Event] {
        guard let blocks = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            switch block["type"] as? String {
            case "text":
                let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : .text(text)
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                let input = block["input"] as? [String: Any] ?? [:]
                return .toolUse(id: id, call: ToolCall(name: name, summary: ToolCall.callSummary(name: name, input: input), result: nil))
            default:
                return nil
            }
        }
    }

    private static func date(_ timestamp: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
            ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
    }
}
