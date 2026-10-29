import SwiftUI
import Transcript

extension PanelController {
    /// The selected agent's Claude Code conversation.
    struct ChatView: View {
        let blocks: [ChatBlock]
        @State private var expansion = ToolGroupExpansion()

        var body: some View {
            // A plain VStack, not a lazy one: the bottom anchor needs every row's real height, and a lazy
            // stack's estimates for long replies left a returning conversation scrolled past its end.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks) { block in
                        ChatBlockView(block: block, isExpanded: expansion.isExpanded(block.id)) {
                            expansion.toggle(block.id)
                        }
                        Hairline()
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    fileprivate struct ChatBlockView: View {
        let block: ChatBlock
        let isExpanded: Bool
        let toggle: () -> Void

        var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }

        @ViewBuilder private var content: some View {
            switch block.kind {
            case .prompt(let text):
                message(label: "you", text: text)
            case .reply(let text):
                message(label: "claude", text: text)
            case .tools(let summary, let calls):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: summary).font(Style.mono(12)).foregroundStyle(Color(Style.mute))
                        Spacer()
                        Button(isExpanded ? "hide" : "show", action: toggle).buttonStyle(GhostButtonStyle())
                    }
                    if isExpanded {
                        ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                            ToolCallView(call: call)
                        }
                    }
                }
            case .turnEnded(let duration):
                Text(verbatim: ChatText.turnMeta(duration: duration, at: block.at, time: TimeText()))
                    .font(Style.mono(12))
                    .foregroundStyle(Color(Style.faint))
            }
        }

        private func message(label: String, text: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: label)
                Text(verbatim: text)
                    .font(Style.sans(15))
                    .foregroundStyle(Color(Style.fg))
                    .textSelection(.enabled)
            }
        }
    }

    fileprivate struct ToolCallView: View {
        let call: ToolCall

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(call.name) · \(call.summary)")
                    .font(Style.mono(12))
                    .foregroundStyle(Color(Style.fg))
                if let result = call.result {
                    Text(verbatim: result)
                        .font(Style.mono(11))
                        .foregroundStyle(Color(Style.faint))
                }
            }
            .textSelection(.enabled)
            .padding(.leading, 12)
        }
    }
}
