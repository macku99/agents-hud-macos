import HUDCore
import SwiftUI
import Transcript

extension PanelController {
    /// Header, status strip, and the roster beside the selected agent's detail.
    struct PanelView: View {
        let store: HUDStore
        let transcripts: any TranscriptSource
        let jump: AgentJump
        let rosterWidthPreference: RosterWidth
        @State private var rosterWidth: CGFloat
        /// Counts refresh presses, so screen text knows to read again.
        @State private var refreshes = 0

        init(store: HUDStore, transcripts: any TranscriptSource, jump: AgentJump, rosterWidthPreference: RosterWidth) {
            self.store = store
            self.transcripts = transcripts
            self.jump = jump
            self.rosterWidthPreference = rosterWidthPreference
            _rosterWidth = State(initialValue: rosterWidthPreference.stored)
        }

        var body: some View {
            VStack(spacing: 0) {
                header
                Hairline()
                statusStrip
                Hairline()
                HStack(spacing: 0) {
                    RosterColumn(store: store).frame(width: rosterWidth)
                    RosterDivider(width: $rosterWidth, preference: rosterWidthPreference)
                    DetailColumn(store: store, transcripts: transcripts, jump: jump, refreshes: refreshes)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(Style.bg))
            .ignoresSafeArea()
        }

        private var header: some View {
            HStack(spacing: 8) {
                HMark()
                Text("agents hud").font(Style.mono(13, .semibold)).foregroundStyle(Color(Style.fg))
                Spacer()
                Button {
                    refreshes += 1
                    Task { await store.refresh() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("refresh")
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }

        private var statusStrip: some View {
            let strip = StatusStrip(roster: store.roster, connections: store.connections)
            return HStack(spacing: 8) {
                Circle().fill(Color(strip.isAvailable ? Style.accent : Style.faint)).frame(width: 6, height: 6)
                Text(verbatim: strip.text).font(Style.mono(12)).foregroundStyle(Color(Style.mute))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
        }
    }
}
