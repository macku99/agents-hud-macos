import HerdrKit
import HUDCore

extension PanelController {
    /// What the detail column shows under the selected agent's title row.
    enum DetailBody: Equatable {
        case blocked
        case chat(AgentSessionRef)
        case screenText
        /// An agent outside herdr whose transcript cannot be shown; there is no screen to read instead.
        case noTranscript

        /// Chat needs a session ref whose transcript is available; otherwise screen text stands in for
        /// a herdr agent. Only herdr can read a blocked agent's question, so other agents show chat.
        init(_ agent: AgentSnapshot, transcript: TranscriptFeed.State) {
            if agent.herdr == nil {
                if let session = agent.transcript, transcript == .available {
                    self = .chat(session)
                } else {
                    self = .noTranscript
                }
            } else if agent.status == .blocked {
                self = .blocked
            } else if let session = agent.transcript, transcript == .available {
                self = .chat(session)
            } else {
                self = .screenText
            }
        }

        /// The meta beside the title row's button when there is no Chat, saying why.
        static func noChatNote(for agent: AgentSnapshot, transcript: TranscriptFeed.State) -> String? {
            switch DetailBody(agent, transcript: transcript) {
            case .screenText:
                if agent.transcript == nil { return "no transcript linked · screen text" }
                return transcript == .ended ? "transcript unavailable · screen text" : "screen text"
            case .noTranscript:
                if agent.transcript == nil { return "no transcript yet" }
                return transcript == .ended ? "transcript unavailable" : "loading transcript"
            case .blocked, .chat:
                return nil
            }
        }

        /// One read of the pane's screen. A different request means the text is read again.
        struct ScreenRequest: Hashable {
            let agent: AgentKey
            let source: ReadSource
            let status: AgentStatus
            let stateChangeSeq: UInt64
            let refreshes: Int
        }

        /// The screen read the body needs, if any. Screen text is read again when the status changes
        /// and on every refresh; the blocked question only when the status changes. Only herdr can read
        /// an agent's screen.
        static func screenRequest(for agent: AgentSnapshot, transcript: TranscriptFeed.State, refreshes: Int) -> ScreenRequest? {
            guard let herdr = agent.herdr else { return nil }
            let source: ReadSource
            let counted: Int
            switch DetailBody(agent, transcript: transcript) {
            case .chat, .noTranscript: return nil
            case .blocked: (source, counted) = (.visible, 0)
            case .screenText: (source, counted) = (.recentUnwrapped, refreshes)
            }
            return ScreenRequest(agent: agent.key, source: source, status: agent.status,
                                 stateChangeSeq: herdr.stateChangeSeq, refreshes: counted)
        }
    }
}
