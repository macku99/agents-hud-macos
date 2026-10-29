import AppKit
import HerdrKit
import HUDCore
import SwiftUI
import Transcript

extension PanelController {
    struct DetailColumn: View {
        let store: HUDStore
        let transcripts: any TranscriptSource
        let jump: AgentJump
        let refreshes: Int
        /// The selected agent's transcript, read here rather than in Chat so screen text can stand in
        /// until it first arrives and after it can no longer be read.
        @State private var feed: TranscriptFeed?

        var body: some View {
            if let entry = store.roster.first(where: { $0.id == store.selectedAgent }) {
                let agent = entry.agent
                let transcript = feed?.state(for: agent.transcript) ?? .waiting
                let screenRequest = DetailBody.screenRequest(for: agent, transcript: transcript, refreshes: refreshes)
                let goToAgent = { jump.go(to: agent) }
                VStack(spacing: 0) {
                    TitleRow(entry: entry,
                             note: DetailBody.noChatNote(for: agent, transcript: transcript),
                             goToAgent: goToAgent)
                    Hairline()
                    Group {
                        switch DetailBody(agent, transcript: transcript) {
                        case .blocked:
                            BlockedCard(store: store, agent: agent, request: screenRequest, goToAgent: goToAgent)
                        case .chat(let session):
                            ChatView(blocks: feed?.blocks ?? []).id(session)
                        case .screenText:
                            ScreenText(store: store, agent: agent.kind, request: screenRequest)
                        case .noTranscript:
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(entry.id)
                    Hairline()
                    // Only herdr takes prompts from the HUD; a Desktop session is answered in Desktop, so
                    // its row ends in a header-height bar holding the way there.
                    switch Destination(of: agent) {
                    case .terminal:
                        PromptBox(store: store, agent: agent).id(entry.id)
                    case .desktop:
                        DesktopFooter(instance: agent.place, goToAgent: goToAgent)
                    }
                }
                .task(id: agent.transcript) { await follow(agent.transcript) }
            } else {
                Color.clear
            }
        }

        private func follow(_ session: AgentSessionRef?) async {
            guard let session else {
                feed = nil
                return
            }
            feed = TranscriptFeed(session: session)
            for await latest in transcripts.chat(at: session, limit: 200) {
                guard !Task.isCancelled else { return }
                feed?.receive(latest)
            }
            // A stream that ends on its own means the transcript could not be found or read.
            guard !Task.isCancelled else { return }
            feed?.end()
        }
    }

    fileprivate struct TitleRow: View {
        let entry: RosterEntry
        let note: String?
        let goToAgent: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.agent.title)
                        .font(Style.sans(17, .medium))
                        .foregroundStyle(Color(Style.fg))
                        .lineLimit(1)
                    if entry.agent.status == .working {
                        TimelineView(.periodic(from: .now, by: 1)) { context in meta(now: context.date) }
                    } else {
                        meta(now: .now)
                    }
                }
                Spacer(minLength: 12)
                if let note {
                    Text(note).font(Style.mono(12)).foregroundStyle(Color(Style.faint))
                }
                if Destination(of: entry.agent) == .terminal {
                    Button { goToAgent() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                            Text("terminal")
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }

        private func meta(now: Date) -> some View {
            Text(verbatim: RosterRow.detailMeta(entry, now: now, time: TimeText(), home: NSHomeDirectory()))
                .font(Style.mono(12))
                .foregroundStyle(Color(Style.faint))
                .lineLimit(1)
        }
    }

    /// The bar a Desktop row ends in, where a herdr row has its prompt box: the row's one action,
    /// styled like Send, naming the instance it brings forward.
    fileprivate struct DesktopFooter: View {
        let instance: String?
        let goToAgent: () -> Void

        var body: some View {
            HStack {
                Spacer()
                Button { goToAgent() } label: {
                    HStack(spacing: 6) {
                        Text("Open in \(instance ?? "Claude")")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
        }
    }

    fileprivate struct BlockedCard: View {
        let store: HUDStore
        let agent: AgentSnapshot
        let request: DetailBody.ScreenRequest?
        let goToAgent: () -> Void
        @State private var question: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    MarkerView(marker: .blocked)
                    SectionLabel(text: "needs input")
                }
                ScrollView {
                    Text(verbatim: question ?? "")
                        .font(Style.mono(13))
                        .foregroundStyle(Color(Style.fg))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                HStack {
                    Spacer()
                    Button { goToAgent() } label: {
                        HStack(spacing: 6) {
                            Text("Go to agent")
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Style.panel)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(Style.line), lineWidth: 1))
            .padding(20)
            .readingScreen(request, from: store, into: $question)
        }
    }

    fileprivate struct ScreenText: View {
        let store: HUDStore
        let agent: String
        let request: DetailBody.ScreenRequest?
        @State private var text: String?

        var body: some View {
            ScrollView {
                Text(verbatim: ScreenChrome.strip(text ?? "", agent: agent))
                    .font(Style.mono(12))
                    .foregroundStyle(Color(Style.fg))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .defaultScrollAnchor(.bottom)
            .readingScreen(request, from: store, into: $text)
        }
    }
}

extension View {
    /// Reads the pane's screen whenever `request` changes; the previous text stays until the new one arrives.
    fileprivate func readingScreen(_ request: PanelController.DetailBody.ScreenRequest?, from store: HUDStore,
                                   into text: Binding<String?>) -> some View {
        task(id: request) {
            guard let request else { return }
            let latest = await store.screenText(for: request.agent, source: request.source)
            // A newer request has started; its read wins even if this one returns later.
            guard !Task.isCancelled else { return }
            text.wrappedValue = latest
        }
    }
}
