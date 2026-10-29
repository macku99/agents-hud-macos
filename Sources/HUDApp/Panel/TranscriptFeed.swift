import HerdrKit
import Transcript

extension PanelController {
    /// The latest Chat blocks of one session's transcript, and how far reading it has got.
    struct TranscriptFeed {
        enum State: Equatable {
            /// Nothing emitted yet.
            case waiting
            case available
            /// The stream ended on its own: the transcript could not be found or read.
            case ended
        }

        let session: AgentSessionRef
        private(set) var blocks: [ChatBlock] = []
        private var hasEmitted = false
        private var hasEnded = false

        init(session: AgentSessionRef) {
            self.session = session
        }

        mutating func receive(_ latest: [ChatBlock]) {
            blocks = latest
            hasEmitted = true
        }

        mutating func end() {
            hasEnded = true
        }

        /// The state for `session`; a feed that belongs to another session has nothing yet for it.
        func state(for session: AgentSessionRef?) -> State {
            guard session == self.session else { return .waiting }
            if hasEnded { return .ended }
            return hasEmitted ? .available : .waiting
        }
    }
}
