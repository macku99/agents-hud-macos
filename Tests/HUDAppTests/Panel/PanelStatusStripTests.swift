import HerdrKit
import HerdrKitTesting
import HUDCore
import Testing
@testable import HUDApp

@Suite struct PanelStatusStripTests {
    private func entry(_ pane: String, _ status: AgentStatus, _ attention: Attention = .none) -> RosterEntry {
        RosterEntry(agent: .fake(pane: pane, status: status), attention: attention, stateSince: nil)
    }

    private func herdr(_ state: SourceState) -> [SourceConnection] {
        [SourceConnection(id: HerdrAgentSource.id(for: .local), label: "herdr", state: state)]
    }

    @Test func countsAgentsAndThoseNeedingAttention() {
        let roster = [entry("w1:p1", .blocked, .blocked), entry("w1:p2", .done, .unseen), entry("w2:p1", .working)]
        let strip = PanelController.StatusStrip(roster: roster, connections: herdr(.connected))
        #expect(strip.text == "this mac · 3 agents · 2 need attention")
        #expect(strip.isAvailable)
    }

    @Test func usesTheSingularForOne() {
        let strip = PanelController.StatusStrip(roster: [entry("w1:p1", .blocked, .blocked)], connections: herdr(.connected))
        #expect(strip.text == "this mac · 1 agent · 1 needs attention")
    }

    @Test func showsZeroCountsForAnEmptyRoster() {
        let strip = PanelController.StatusStrip(roster: [], connections: herdr(.connected))
        #expect(strip.text == "this mac · 0 agents · 0 need attention")
    }

    @Test func saysWhileItIsConnecting() {
        let strip = PanelController.StatusStrip(roster: [], connections: herdr(.connecting))
        #expect(strip.text == "this mac · connecting to herdr")
        #expect(strip.isAvailable)
    }

    @Test func saysWhyASourceIsUnavailable() {
        let strip = PanelController.StatusStrip(roster: [entry("w1:p1", .idle)],
                                                connections: herdr(.unavailable("herdr is not reachable")))
        #expect(strip.text == "this mac · herdr is not reachable")
        #expect(!strip.isAvailable)
    }
}
