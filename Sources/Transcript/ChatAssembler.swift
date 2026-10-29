import Foundation

/// Turns transcript lines, fed in file order, into chat blocks. Each turn shows as its prompt and any
/// prompts queued while it ran, one line folding every tool call of the turn, one reply joining the
/// turn's text, and its end.
struct ChatAssembler {
    private struct Turn {
        var prompt: ChatBlock?
        var queued: [ChatBlock] = []
        var startedAt: Date?
        var lastAssistantAt: Date?
        var tools: (id: String, at: Date?, calls: [ToolCall])?
        var reply: (id: String, at: Date?, text: String)?
        var end: ChatBlock?

        var blocks: [ChatBlock] {
            var blocks: [ChatBlock] = []
            if let prompt { blocks.append(prompt) }
            blocks += queued
            if let tools {
                blocks.append(ChatBlock(id: tools.id, kind: .tools(summary: ToolCall.groupSummary(of: tools.calls), calls: tools.calls),
                                        at: tools.at))
            }
            if let reply { blocks.append(ChatBlock(id: reply.id, kind: .reply(reply.text), at: reply.at)) }
            if let end { blocks.append(end) }
            return blocks
        }
    }

    private var turns: [Turn] = []
    /// Where each tool call still waiting for its result sits: its turn and its place in that turn's calls.
    private var awaitingResults: [String: (turn: Int, call: Int)] = [:]

    var blocks: [ChatBlock] { turns.flatMap(\.blocks) }

    mutating func consume(_ line: TranscriptLine) {
        for (index, event) in line.events.enumerated() {
            let id = index == 0 ? line.uuid : "\(line.uuid)#\(index)"
            apply(event, id: id, at: line.at)
        }
        if line.role == .assistant, !turns.isEmpty, turns[turns.count - 1].end == nil {
            turns[turns.count - 1].lastAssistantAt = line.at
        }
    }

    private mutating func apply(_ event: TranscriptLine.Event, id: String, at: Date?) {
        switch event {
        case .prompt(let text):
            endTurnWithoutMarker()
            turns.append(Turn(prompt: ChatBlock(id: id, kind: .prompt(text), at: at), startedAt: at))

        case .queuedPrompt(let text):
            // Claude Code delivers it between tool calls of the running turn, whose marker still
            // measures the whole turn; with no turn running it starts one like a typed prompt.
            guard let last = turns.indices.last, turns[last].end == nil else {
                return apply(.prompt(text), id: id, at: at)
            }
            turns[last].queued.append(ChatBlock(id: id, kind: .prompt(text), at: at))

        case .text(let text):
            let current = openTurn()
            if let reply = turns[current].reply {
                turns[current].reply = (reply.id, reply.at, reply.text + "\n\n" + text)
            } else {
                turns[current].reply = (id, at, text)
            }

        case .toolUse(let toolUseID, let call):
            let current = openTurn()
            let tools = turns[current].tools ?? (id, at, [])
            awaitingResults[toolUseID] = (current, tools.calls.count)
            turns[current].tools = (tools.id, tools.at, tools.calls + [call])

        case .toolResult(let toolUseID, let text):
            guard let position = awaitingResults.removeValue(forKey: toolUseID),
                  let tools = turns[position.turn].tools
            else { return }
            var calls = tools.calls
            let call = calls[position.call]
            calls[position.call] = ToolCall(name: call.name, summary: call.summary, result: text)
            turns[position.turn].tools = (tools.id, tools.at, calls)

        case .turnEnded(let duration):
            let current = openTurn()
            turns[current].end = ChatBlock(id: id, kind: .turnEnded(duration: duration), at: at)
        }
    }

    /// The turn still collecting events. Assistant output after a turn has ended, such as a turn a
    /// notification started, opens a turn without a prompt.
    private mutating func openTurn() -> Int {
        if turns.last == nil || turns[turns.count - 1].end != nil { turns.append(Turn()) }
        return turns.count - 1
    }

    /// Claude Code doesn't always write a duration marker, so a turn that never got one ends at
    /// the last assistant entry before the next prompt.
    private mutating func endTurnWithoutMarker() {
        guard let last = turns.indices.last, turns[last].end == nil,
              let prompt = turns[last].prompt, let start = turns[last].startedAt, let end = turns[last].lastAssistantAt
        else { return }
        let milliseconds = max(0, Int64((end.timeIntervalSince(start) * 1000).rounded()))
        turns[last].end = ChatBlock(id: "\(prompt.id)#end", kind: .turnEnded(duration: .milliseconds(milliseconds)), at: end)
    }
}
