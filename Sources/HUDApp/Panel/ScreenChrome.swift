import Foundation

extension PanelController {
    /// Claude Code draws its input box, status line and buttons below the conversation, right-aligned
    /// notices just above the box, and mods draw their panes as rounded boxes around the prompt. Screen
    /// text is shown for the conversation, so all of that goes.
    ///
    /// Claude Code starts each conversation entry at column 0 with a marker (`⏺`, or `●` off macOS, for
    /// output, `❯` a prompt, `!` a shell command, `※` a recap, a spinner frame while it works) and
    /// indents everything else. Its input box is drawn at column 0 too. So a box at column 0 with no
    /// entry after it is a mod's pane, while a box, rule or choice inside a reply is indented and stays.
    /// When a rule is unsure, it keeps the line: showing some chrome is better than hiding what the
    /// agent said.
    enum ScreenChrome {
        /// Leading spaces that mark a right-aligned notice rather than indented output.
        private static let noticeIndent = 20
        /// How far short of the input box's right edge a right-aligned notice may end.
        private static let noticeSlack = 4
        private static let entryMarkers: Set<Character> = ["⏺", "●", "❯", "!", "※", "·", "✢", "✳", "✶", "✻", "✽", "*"]
        /// The input box's prompt: `!` while the box is in shell mode.
        private static let boxPrompts: Set<Character> = ["❯", "!"]

        static func strip(_ text: String, agent: String) -> String {
            guard agent == "claude" else { return text }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            var boxWidth: Int?
            if let box = inputBoxStart(lines) {
                boxWidth = lines[box...].filter(isRule).map { $0.trimmingCharacters(in: .whitespaces).count }.max()
                lines.removeSubrange(box...)
            }
            if let pane = lastPaneStart(lines) { lines.removeSubrange(pane...) }
            while let last = lines.last {
                if last.allSatisfy(\.isWhitespace) || isNotice(last, boxWidth: boxWidth) {
                    lines.removeLast()
                } else if let pane = paneEnding(at: lines.count - 1, in: lines) {
                    lines.removeSubrange(pane...)
                } else {
                    break
                }
            }
            return lines.joined(separator: "\n")
        }

        /// The rule above Claude Code's last input line. A prompt line with no rule directly above it
        /// is an earlier entry in the conversation; a box with conversation after it was left behind
        /// by a redraw, and the current box is missing.
        private static func inputBoxStart(_ lines: [Substring]) -> Int? {
            for prompt in lines.indices.reversed() where lines[prompt].first.map(boxPrompts.contains) ?? false {
                var start = prompt
                while start > lines.startIndex, isRule(lines[start - 1]) { start -= 1 }
                guard start < prompt else { continue }
                return lines[(prompt + 1)...].contains(where: isConversation) ? nil : start
            }
            return nil
        }

        /// The top of the last box at column 0 when no conversation follows it: a mod's pane, with
        /// the status lines and buttons Claude Code draws below it.
        private static func lastPaneStart(_ lines: [Substring]) -> Int? {
            guard let bottom = lines.lastIndex(where: { $0.hasPrefix("╰") }),
                  !lines[(bottom + 1)...].contains(where: isConversation)
            else { return nil }
            return paneEnding(at: bottom, in: lines)
        }

        private static func paneEnding(at bottom: Int, in lines: [Substring]) -> Int? {
            guard lines[bottom].hasPrefix("╰") else { return nil }
            return lines[..<bottom].lastIndex { $0.hasPrefix("╭") }
        }

        private static func isConversation(_ line: Substring) -> Bool {
            line.first.map(entryMarkers.contains) ?? false
        }

        /// Indented far and ending at the input box's right edge. Without the box there is no edge to
        /// measure against, so nothing counts as a notice.
        private static func isNotice(_ line: Substring, boxWidth: Int?) -> Bool {
            guard let boxWidth else { return false }
            let end = line.reversed().drop(while: \.isWhitespace).count
            return line.prefix(while: { $0 == " " }).count >= noticeIndent && (boxWidth - noticeSlack...boxWidth).contains(end)
        }

        /// A rule of the input box, which starts at column 0.
        private static func isRule(_ line: Substring) -> Bool {
            let rule = line.reversed().drop(while: \.isWhitespace)
            return !rule.isEmpty && rule.allSatisfy { $0 == "─" || $0 == "━" }
        }
    }
}
