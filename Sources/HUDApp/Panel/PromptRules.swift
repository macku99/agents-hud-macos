import AppKit
import HerdrKit
import HUDCore

extension PanelController {
    enum PromptRules {
        enum ReturnKey: Equatable {
            case send
            case insertNewline
            /// An input method is composing; Return confirms its candidate.
            case inputMethod
        }

        static func returnKey(modifiers: NSEvent.ModifierFlags, isComposing: Bool) -> ReturnKey {
            if isComposing { return .inputMethod }
            return modifiers.isDisjoint(with: [.shift, .control, .command, .option]) ? .send : .insertNewline
        }

        private static let returnKeyCodes: Set<UInt16> = [36, 76]
        private static let returnCommands: Set<Selector> = [
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
            #selector(NSResponder.insertLineBreak(_:)),
            Selector(("noop:")),
        ]

        /// Whether a text command came from Return or keypad Enter. Handling Return as a command rather
        /// than a key lets an input method commit its text first (Hangul commits, then inserts a newline).
        static func isReturnCommand(_ command: Selector, keyCode: UInt16?) -> Bool {
            guard let keyCode, returnKeyCodes.contains(keyCode) else { return false }
            return returnCommands.contains(command)
        }

        static func canSend(status: AgentStatus, sendState: SendState, draft: String) -> Bool {
            guard status == .idle || status == .done else { return false }
            switch sendState {
            case .ready, .refused: break
            case .sending, .uncertain: return false
            }
            return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// Why a send wrote nothing; the draft stays, so the line says what to fix before sending again.
        static func refusalText(_ reason: RefusalReason) -> String {
            let why = switch reason {
            case .agentChanged: "this pane now runs a different agent"
            case .notReady(let status): "the agent is \(status.rawValue)"
            case .invalidText(let problem): problem
            case .unreachable: "herdr is not reachable"
            case .rejected(let detail): "herdr refused it (\(detail))"
            }
            return "Not sent · \(why)"
        }

        static func refusalLine(_ sendState: SendState) -> String? {
            if case .refused(let reason) = sendState { return refusalText(reason) }
            return nil
        }

        /// A blocked agent is answered in herdr, so its prompt box takes no typing; a working agent's
        /// does, so the next prompt can be drafted while it works.
        static func acceptsTyping(status: AgentStatus) -> Bool {
            status != .blocked
        }

        /// The HUD is an accessory app with no Edit menu, which is what normally turns ⌘V and the other
        /// edit shortcuts into actions, so the prompt field maps them itself.
        static func editAction(key: String, modifiers: NSEvent.ModifierFlags) -> Selector? {
            let modifiers = modifiers.intersection([.command, .shift, .option, .control])
            switch (key.lowercased(), modifiers) {
            case ("v", .command): return #selector(NSText.paste(_:))
            case ("c", .command): return #selector(NSText.copy(_:))
            case ("x", .command): return #selector(NSText.cut(_:))
            case ("a", .command): return #selector(NSResponder.selectAll(_:))
            case ("z", .command): return Selector(("undo:"))
            case ("z", [.command, .shift]): return Selector(("redo:"))
            default: return nil
            }
        }

        static func showsUncertainNote(_ sendState: SendState) -> Bool {
            if case .uncertain = sendState { return true }
            return false
        }
    }
}
