import AppKit
import HerdrKit
import HUDCore
import SwiftUI

extension PanelController {
    struct PromptBox: View {
        let store: HUDStore
        let agent: AgentSnapshot
        @State private var isFocused = false

        var body: some View {
            let pane = agent.key
            let sendState = store.sendState(for: pane)
            let canSend = PromptRules.canSend(status: agent.status, sendState: sendState, draft: store.draft(for: pane))
            VStack(alignment: .trailing, spacing: 10) {
                if PromptRules.showsUncertainNote(sendState) {
                    UncertainNote { store.reconcile(pane) }
                }
                PromptField(
                    text: Binding(get: { store.draft(for: pane) }, set: { store.setDraft($0, for: pane) }),
                    isEditable: PromptRules.acceptsTyping(status: agent.status),
                    isFocused: $isFocused,
                    send: send
                )
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(Style.panel)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(isFocused ? Style.accent : Style.line), lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(Style.soft), lineWidth: 3)
                        .padding(-2)
                        .opacity(isFocused ? 1 : 0)
                )
                HStack(spacing: 12) {
                    if let refusal = PromptRules.refusalLine(sendState) {
                        Text(verbatim: refusal)
                            .font(Style.sans(13))
                            .foregroundStyle(Color(Style.danger))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: send) { Text("Send prompt ↵") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.5)
                }
            }
            .padding(16)
        }

        /// Reads the draft and send state from the store at the moment of sending; the agent's status
        /// comes from this render, and `HUDStore.send` checks it again against the roster.
        private func send() {
            let pane = agent.key
            guard PromptRules.canSend(status: agent.status, sendState: store.sendState(for: pane),
                                      draft: store.draft(for: pane)) else { return }
            Task { await store.send(for: pane) }
        }
    }

    fileprivate struct UncertainNote: View {
        let checked: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivery uncertain").font(Style.sans(15, .medium)).foregroundStyle(Color(Style.danger))
                    Text("The last prompt may have arrived. Check the agent in herdr before sending again.")
                        .font(Style.sans(13))
                        .foregroundStyle(Color(Style.mute))
                }
                Spacer(minLength: 0)
                Button("i checked herdr", action: checked).buttonStyle(GhostButtonStyle())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(Style.line), lineWidth: 1))
        }
    }

    /// A multi-line plain-text field where Return sends and a modified Return inserts a newline.
    fileprivate struct PromptField: NSViewRepresentable {
        @Binding var text: String
        let isEditable: Bool
        @Binding var isFocused: Bool
        let send: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSScrollView {
            let textView = PromptTextView()
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.font = Style.sansFont(15)
            textView.textColor = Style.fg
            textView.insertionPointColor = Style.fg
            textView.textContainerInset = NSSize(width: 6, height: 8)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.minSize = .zero
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            context.coordinator.field = self
            guard let textView = scrollView.documentView as? PromptTextView else { return }
            textView.onSend = send
            textView.onFocusChange = { focused in isFocused = focused }
            textView.isEditable = isEditable
            scrollView.alphaValue = isEditable ? 1 : 0.5
            if !textView.hasMarkedText(), textView.string != text {
                textView.string = text
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            var field: PromptField

            init(_ field: PromptField) { self.field = field }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                field.text = textView.string
            }
        }
    }

    fileprivate final class PromptTextView: NSTextView {
        var onSend: (() -> Void)?
        var onFocusChange: ((Bool) -> Void)?

        override func doCommand(by command: Selector) {
            let event = NSApp.currentEvent.flatMap { $0.type == .keyDown ? $0 : nil }
            guard let event, PromptRules.isReturnCommand(command, keyCode: event.keyCode) else {
                return super.doCommand(by: command)
            }
            switch PromptRules.returnKey(modifiers: event.modifierFlags, isComposing: hasMarkedText()) {
            case .inputMethod: super.doCommand(by: command)
            case .insertNewline: insertNewlineIgnoringFieldEditor(nil)
            case .send: onSend?()
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self,
               let action = PromptRules.editAction(key: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags),
               tryToPerform(action, with: self) {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocusChange?(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange?(false) }
            return resigned
        }
    }
}
