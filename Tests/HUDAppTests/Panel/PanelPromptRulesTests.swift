import AppKit
import HerdrKit
import HUDCore
import Testing
@testable import HUDApp

@Suite struct PanelPromptRulesTests {
    private typealias Rules = PanelController.PromptRules

    @Test func plainEnterSends() {
        #expect(Rules.returnKey(modifiers: [], isComposing: false) == .send)
    }

    @Test func enterIgnoresModifiersThatDoNotMeanNewline() {
        #expect(Rules.returnKey(modifiers: [.capsLock, .numericPad, .function], isComposing: false) == .send)
    }

    @Test(arguments: [NSEvent.ModifierFlags.shift, .control, .command, .option, [.shift, .command]])
    func modifiedEnterInsertsANewline(modifiers: NSEvent.ModifierFlags) {
        #expect(Rules.returnKey(modifiers: modifiers, isComposing: false) == .insertNewline)
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .shift])
    func enterWhileComposingBelongsToTheInputMethod(modifiers: NSEvent.ModifierFlags) {
        #expect(Rules.returnKey(modifiers: modifiers, isComposing: true) == .inputMethod)
    }

    /// Return reaches the text view as one of these commands, depending on modifiers and on whether
    /// an input method committed text first.
    @Test(arguments: ["insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:", "noop:"],
          [UInt16(36), 76])
    func returnAndEnterCommandsAreHandledAsReturn(command: String, keyCode: UInt16) {
        #expect(Rules.isReturnCommand(NSSelectorFromString(command), keyCode: keyCode))
    }

    @Test func otherCommandsAreLeftToTheTextView() {
        #expect(!Rules.isReturnCommand(NSSelectorFromString("insertTab:"), keyCode: 48))
        #expect(!Rules.isReturnCommand(NSSelectorFromString("deleteBackward:"), keyCode: 51))
    }

    @Test func aNewlineCommandFromAnotherKeyIsLeftToTheTextView() {
        #expect(!Rules.isReturnCommand(NSSelectorFromString("insertNewline:"), keyCode: 46))
        #expect(!Rules.isReturnCommand(NSSelectorFromString("insertNewline:"), keyCode: nil))
    }

    @Test(arguments: [AgentStatus.idle, .done])
    func sendsFromAnIdleOrDoneAgent(status: AgentStatus) {
        #expect(Rules.canSend(status: status, sendState: .ready, draft: "go on"))
    }

    @Test(arguments: [AgentStatus.working, .blocked, .unknown])
    func doesNotSendToABusyOrUnknownAgent(status: AgentStatus) {
        #expect(!Rules.canSend(status: status, sendState: .ready, draft: "go on"))
    }

    @Test func sendsAgainAfterARefusal() {
        #expect(Rules.canSend(status: .idle, sendState: .refused(.agentChanged), draft: "go on"))
    }

    @Test(arguments: [SendState.sending, .uncertain("timed out")])
    func doesNotSendWhileSendingOrUncertain(sendState: SendState) {
        #expect(!Rules.canSend(status: .idle, sendState: sendState, draft: "go on"))
    }

    @Test(arguments: ["", "   ", "\n\t \n"])
    func doesNotSendABlankDraft(draft: String) {
        #expect(!Rules.canSend(status: .idle, sendState: .ready, draft: draft))
    }

    @Test func showsTheUncertainNoteOnlyForUncertainDelivery() {
        #expect(Rules.showsUncertainNote(.uncertain("timed out")))
        #expect(!Rules.showsUncertainNote(.ready))
        #expect(!Rules.showsUncertainNote(.sending))
        #expect(!Rules.showsUncertainNote(.refused(.notReady(.working))))
    }

    @Test(arguments: [
        (RefusalReason.agentChanged, "Not sent · this pane now runs a different agent"),
        (.notReady(.working), "Not sent · the agent is working"),
        (.notReady(.blocked), "Not sent · the agent is blocked"),
        (.invalidText("too long"), "Not sent · too long"),
        (.unreachable("connection refused"), "Not sent · herdr is not reachable"),
        (.rejected("agent_blocked: waiting at a dialog"), "Not sent · herdr refused it (agent_blocked: waiting at a dialog)"),
    ])
    func aRefusalSaysWhyNothingWasSent(reason: RefusalReason, text: String) {
        #expect(Rules.refusalText(reason) == text)
    }

    @Test func onlyARefusedStateHasARefusalLine() {
        #expect(Rules.refusalLine(.refused(.agentChanged)) == "Not sent · this pane now runs a different agent")
        #expect(Rules.refusalLine(.ready) == nil)
        #expect(Rules.refusalLine(.sending) == nil)
        #expect(Rules.refusalLine(.uncertain("timeout")) == nil)
    }

    @Test func theFieldTakesNoTypingWhileTheAgentIsBlocked() {
        #expect(Rules.acceptsTyping(status: .blocked) == false)
        #expect(Rules.acceptsTyping(status: .working))
        #expect(Rules.acceptsTyping(status: .idle))
        #expect(Rules.acceptsTyping(status: .done))
    }

    @Test(arguments: [
        ("v", NSEvent.ModifierFlags.command, "paste:"),
        ("c", NSEvent.ModifierFlags.command, "copy:"),
        ("x", NSEvent.ModifierFlags.command, "cut:"),
        ("a", NSEvent.ModifierFlags.command, "selectAll:"),
        ("z", NSEvent.ModifierFlags.command, "undo:"),
        ("z", NSEvent.ModifierFlags([.command, .shift]), "redo:"),
        ("V", NSEvent.ModifierFlags([.command, .capsLock]), "paste:"),
    ])
    func standardEditShortcutsMapToTheirActions(key: String, modifiers: NSEvent.ModifierFlags, action: String) {
        #expect(Rules.editAction(key: key, modifiers: modifiers) == Selector((action)))
    }

    @Test(arguments: [
        ("v", NSEvent.ModifierFlags()),
        ("v", NSEvent.ModifierFlags.control),
        ("v", NSEvent.ModifierFlags([.command, .option])),
        ("q", NSEvent.ModifierFlags.command),
        ("h", NSEvent.ModifierFlags([.command, .control, .option])),
    ])
    func otherKeysAreNotEditShortcuts(key: String, modifiers: NSEvent.ModifierFlags) {
        #expect(Rules.editAction(key: key, modifiers: modifiers) == nil)
    }
}
