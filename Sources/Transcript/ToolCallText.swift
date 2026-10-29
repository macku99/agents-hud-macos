import Foundation

extension ToolCall {
    private enum Kind: Hashable {
        case read, edited, ranShell, searched
        case other(String)

        init(toolName: String) {
            switch toolName {
            case "Read": self = .read
            case "Edit", "Write", "MultiEdit", "NotebookEdit": self = .edited
            case "Bash": self = .ranShell
            case "Grep", "Glob": self = .searched
            default: self = .other(toolName)
            }
        }

        func phrase(count: Int) -> String {
            switch self {
            case .read: "read \(count) \(count == 1 ? "file" : "files")"
            case .edited: "edited \(count) \(count == 1 ? "file" : "files")"
            case .ranShell: "ran \(count) shell \(count == 1 ? "command" : "commands")"
            case .searched: count == 1 ? "searched once" : "searched \(count) times"
            case .other(let name): count == 1 ? "used \(name)" : "used \(name) \(count) times"
            }
        }
    }

    private static let callSummaryLimit = 200
    private static let resultLineLimit = 3
    private static let resultCharacterLimit = 300

    /// "read 2 files · ran 4 shell commands", kinds in the order they were first used.
    static func groupSummary(of calls: [ToolCall]) -> String {
        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        for call in calls {
            let kind = Kind(toolName: call.name)
            if counts[kind] == nil { order.append(kind) }
            counts[kind, default: 0] += 1
        }
        return order.map { $0.phrase(count: counts[$0]!) }.joined(separator: " · ")
    }

    /// The input field that best says what a call did, cut to one line.
    static func callSummary(name: String, input: [String: Any]) -> String {
        let keys: [String] = switch name {
        case "Bash": ["command"]
        case "Read", "Edit", "Write", "MultiEdit": ["file_path"]
        case "NotebookEdit": ["notebook_path"]
        case "Grep", "Glob": ["pattern"]
        default: ["description", "url", "query", "command", "file_path", "pattern", "skill"]
        }
        guard let value = keys.lazy.compactMap({ input[$0] as? String }).first else { return "" }
        let firstLine = value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return cut(firstLine.trimmingCharacters(in: .whitespaces), to: callSummaryLimit)
    }

    /// The start of a tool's output: at most three lines and 300 characters, marked with "…" when cut.
    static func shortenedResult(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.allSatisfy(\.isWhitespace) else { return nil }
        let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let kept = lines.prefix(resultLineLimit).joined(separator: "\n")
        let short = cut(kept, to: resultCharacterLimit)
        return lines.count > resultLineLimit && short == kept ? kept + "…" : short
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
