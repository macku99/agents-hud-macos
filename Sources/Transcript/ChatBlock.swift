import Foundation
import HerdrKit

/// One tool call inside a folded tool group: what ran, and a shortened result.
public struct ToolCall: Hashable, Sendable {
    public let name: String
    public let summary: String
    public let result: String?

    public init(name: String, summary: String, result: String?) {
        self.name = name
        self.summary = summary
        self.result = result
    }
}

/// One unit of a Claude Code conversation as Chat shows it.
public struct ChatBlock: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case prompt(String)
        case reply(String)
        /// A turn's tool calls folded into one line ("read 2 files · ran 4 shell commands").
        case tools(summary: String, calls: [ToolCall])
        case turnEnded(duration: Duration)
    }

    /// Stable across re-reads of the same transcript, so expanded tool groups stay expanded.
    public let id: String
    public let kind: Kind
    public let at: Date?

    public init(id: String, kind: Kind, at: Date?) {
        self.id = id
        self.kind = kind
        self.at = at
    }
}

public protocol TranscriptSource: Sendable {
    /// The last `limit` blocks of the conversation `ref` points at, emitted again whenever the
    /// transcript grows. The stream ends when the transcript cannot be found or read.
    func chat(at ref: AgentSessionRef, limit: Int) -> AsyncStream<[ChatBlock]>
}
