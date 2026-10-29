import Foundation
@testable import Transcript

/// Synthetic Claude Code transcript lines, shaped like the real JSONL but with made-up values.
enum TranscriptFixture {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func time(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    static func timestamp(_ seconds: Double) -> String {
        time(seconds).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func prompt(_ uuid: String, _ text: String, at seconds: Double = 0, extra: [String: Any] = [:]) -> String {
        user(uuid, content: text, at: seconds, extra: extra)
    }

    static func user(_ uuid: String, content: Any, at seconds: Double = 0, extra: [String: Any] = [:]) -> String {
        entry([
            "type": "user", "uuid": uuid, "timestamp": timestamp(seconds), "isSidechain": false,
            "sessionId": "session-1", "message": ["role": "user", "content": content],
        ], extra)
    }

    static func assistant(_ uuid: String, _ blocks: [[String: Any]], at seconds: Double = 0,
                          message: String = "msg-1", extra: [String: Any] = [:]) -> String {
        entry([
            "type": "assistant", "uuid": uuid, "timestamp": timestamp(seconds), "isSidechain": false,
            "sessionId": "session-1",
            "message": ["id": message, "role": "assistant", "type": "message", "content": blocks, "stop_reason": "tool_use"],
        ], extra)
    }

    /// A prompt typed while Claude was working, recorded when Claude Code delivers it.
    static func queuedCommand(_ uuid: String, prompt: Any, mode: String = "prompt", origin: [String: Any]? = ["kind": "human"],
                              at seconds: Double = 0, extra: [String: Any] = [:]) -> String {
        var attachment: [String: Any] = [
            "type": "queued_command", "commandMode": mode, "prompt": prompt,
            "source_uuid": "source-\(uuid)", "timestamp": timestamp(seconds),
        ]
        attachment["origin"] = origin
        return entry([
            "type": "attachment", "uuid": uuid, "timestamp": timestamp(seconds), "isSidechain": false,
            "sessionId": "session-1", "attachment": attachment,
        ], extra)
    }

    static func turnDuration(_ uuid: String, milliseconds: Int, at seconds: Double = 0) -> String {
        entry([
            "type": "system", "subtype": "turn_duration", "uuid": uuid, "timestamp": timestamp(seconds),
            "durationMs": milliseconds, "isMeta": false, "isSidechain": false, "messageCount": 4,
        ], [:])
    }

    static func text(_ text: String) -> [String: Any] { ["type": "text", "text": text] }

    static func thinking() -> [String: Any] { ["type": "thinking", "thinking": "synthetic", "signature": "sig"] }

    static func toolUse(_ id: String, _ name: String, _ input: [String: Any]) -> [String: Any] {
        ["type": "tool_use", "id": id, "name": name, "input": input, "caller": ["type": "direct"]]
    }

    static func toolResult(_ toolUseID: String, _ content: Any) -> [String: Any] {
        ["type": "tool_result", "tool_use_id": toolUseID, "content": content, "is_error": false]
    }

    static func entry(_ fields: [String: Any], _ extra: [String: Any]) -> String {
        let merged = fields.merging(extra) { _, new in new }
        let data = try! JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func blocks(_ lines: [String]) -> [ChatBlock] {
        var assembler = ChatAssembler()
        for line in lines {
            if let parsed = TranscriptLine(Data(line.utf8)) { assembler.consume(parsed) }
        }
        return assembler.blocks
    }
}
