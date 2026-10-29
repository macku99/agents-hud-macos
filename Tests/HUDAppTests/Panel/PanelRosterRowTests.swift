import Foundation
import HerdrKit
import HerdrKitTesting
import HUDCore
import Testing
@testable import HUDApp

@Suite struct PanelRosterRowTests {
    private let time = PanelController.TimeText(timeZone: TimeZone(identifier: "UTC")!)
    /// 16:02:00 UTC
    private let since = Date(timeIntervalSince1970: 1_800_000_000 + 8 * 3600 + 2 * 60)

    private func row(_ status: AgentStatus, _ attention: Attention = .none, since: Date? = nil,
                     cwd: String? = "/Users/m/Work/herdr-hud", now: Date? = nil) -> PanelController.RosterRow {
        let entry = RosterEntry(agent: .fake(pane: "w2:p1", status: status, title: "Fix the parser", cwd: cwd),
                                attention: attention, stateSince: since ?? self.since)
        return PanelController.RosterRow(entry, now: now ?? self.since.addingTimeInterval(192), time: time)
    }

    @Test func blockedShowsTheSquareAndNeedsInput() {
        let blocked = row(.blocked, .blocked)
        #expect(blocked.marker == .blocked)
        #expect(blocked.stateLine == "blocked · needs input · 16:02")
    }

    @Test func blockedStatusWinsEvenBeforeAttentionCatchesUp() {
        #expect(row(.blocked, .none).marker == .blocked)
    }

    @Test func unseenShowsTheAccentDot() {
        let unseen = row(.done, .unseen)
        #expect(unseen.marker == .unseen)
        #expect(unseen.stateLine == "done · unseen · 16:02")
    }

    @Test func workingShowsALiveTimerFromStateSince() {
        let working = row(.working)
        #expect(working.marker == .working)
        #expect(working.stateLine == "working · 3:12")
    }

    @Test func settledStatusesShowTheHollowRingAndClock() {
        #expect(row(.done).marker == .settled)
        #expect(row(.done).stateLine == "done · 16:02")
        #expect(row(.idle).marker == .settled)
        #expect(row(.idle).stateLine == "idle · 16:02")
        #expect(row(.unknown).marker == .settled)
        #expect(row(.unknown).stateLine == "unknown · 16:02")
    }

    /// Every status and attention pair. Some (working and unseen) never come from HUDCore; they are
    /// pinned so the precedence stays deliberate: blocked, then unseen, then working, then the status.
    @Test(arguments: [
        (AgentStatus.idle, Attention.none, PanelController.RosterRow.Marker.settled, "idle · 16:02"),
        (.idle, .unseen, .unseen, "done · unseen · 16:02"),
        (.idle, .blocked, .blocked, "blocked · needs input · 16:02"),
        (.working, .none, .working, "working · 3:12"),
        (.working, .unseen, .unseen, "done · unseen · 16:02"),
        (.working, .blocked, .blocked, "blocked · needs input · 16:02"),
        (.blocked, .none, .blocked, "blocked · needs input · 16:02"),
        (.blocked, .unseen, .blocked, "blocked · needs input · 16:02"),
        (.blocked, .blocked, .blocked, "blocked · needs input · 16:02"),
        (.done, .none, .settled, "done · 16:02"),
        (.done, .unseen, .unseen, "done · unseen · 16:02"),
        (.done, .blocked, .blocked, "blocked · needs input · 16:02"),
        (.unknown, .none, .settled, "unknown · 16:02"),
        (.unknown, .unseen, .unseen, "done · unseen · 16:02"),
        (.unknown, .blocked, .blocked, "blocked · needs input · 16:02"),
    ])
    func everyStatusAndAttentionGetsAMarkerAndStateLine(status: AgentStatus, attention: Attention,
                                                        marker: PanelController.RosterRow.Marker, stateLine: String) {
        let result = row(status, attention)
        #expect(result.marker == marker)
        #expect(result.stateLine == stateLine)
    }

    @Test func stateLineOmitsTheTimeWhenStateSinceIsUnknown() {
        let entry = RosterEntry(agent: .fake(pane: "w2:p1", status: .working), attention: .none, stateSince: nil)
        #expect(PanelController.RosterRow(entry, now: since, time: time).stateLine == "working")
    }

    @Test func metaLineNamesWorkspaceProjectAndAgent() {
        let entry = row(.idle)
        #expect(entry.title == "Fix the parser")
        #expect(entry.meta == "w2 · herdr-hud · claude")
    }

    @Test func projectIgnoresATrailingSlash() {
        #expect(row(.idle, cwd: "/Users/m/Work/herdr-hud/").meta == "w2 · herdr-hud · claude")
    }

    @Test func metaLineSkipsTheProjectWithoutACwd() {
        #expect(row(.idle, cwd: nil).meta == "w2 · claude")
        #expect(row(.idle, cwd: "").meta == "w2 · claude")
    }

    @Test func detailMetaShowsTheHomeRelativePathAndState() {
        let entry = RosterEntry(agent: .fake(pane: "w2:p1", status: .working, cwd: "/Users/m/Work/herdr-hud"),
                                attention: .none, stateSince: since)
        let meta = PanelController.RosterRow.detailMeta(entry, now: since.addingTimeInterval(192), time: time,
                                                        home: "/Users/m")
        #expect(meta == "w2 · ~/Work/herdr-hud · claude · working 3:12")
    }

    @Test func detailMetaKeepsPathsOutsideHomeAndTheHomeItself() {
        func meta(_ cwd: String?) -> String {
            let entry = RosterEntry(agent: .fake(pane: "w2:p1", status: .done, cwd: cwd), attention: .unseen,
                                    stateSince: since)
            return PanelController.RosterRow.detailMeta(entry, now: since, time: time, home: "/Users/m")
        }
        #expect(meta("/tmp/scratch") == "w2 · /tmp/scratch · claude · done 16:02")
        #expect(meta("/Users/m") == "w2 · ~ · claude · done 16:02")
        #expect(meta("/Users/mx/app") == "w2 · /Users/mx/app · claude · done 16:02")
        #expect(meta(nil) == "w2 · claude · done 16:02")
    }
}
