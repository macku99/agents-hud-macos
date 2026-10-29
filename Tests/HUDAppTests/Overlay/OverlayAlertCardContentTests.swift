import Foundation
import HerdrKit
import HerdrKitTesting
import HUDCore
import Testing
@testable import HUDApp

@Suite struct OverlayAlertCardContentTests {
    typealias Content = OverlayController.AlertCardContent

    private let utc = TimeZone(identifier: "UTC")!

    private func alert(_ pane: String, _ kind: HUDAlert.Kind, minute: Int, preview: String = "") -> HUDAlert {
        HUDAlert(key: .herdr(pane), kind: kind, title: "title \(pane)", preview: preview,
                 at: Date(timeIntervalSince1970: TimeInterval(16 * 3600 + minute * 60)))
    }

    private func entry(_ pane: String, cwd: String?) -> RosterEntry {
        RosterEntry(agent: .fake(pane: pane, cwd: cwd), attention: .none, stateSince: nil)
    }

    @Test func newestAlertComesFirstSoItSitsNearestH() {
        let older = alert("w1:p1", .finished, minute: 1)
        let newer = alert("w1:p2", .needsInput, minute: 3)
        let cards = Content.cards(for: [older, newer], roster: [], timeZone: utc)
        #expect(cards.map(\.id) == [newer.id, older.id])
    }

    @Test func cardCarriesTitleMarkerAndPane() {
        let needsInput = alert("w1:p2", .needsInput, minute: 3)
        let card = Content.cards(for: [needsInput], roster: [], timeZone: utc)[0]
        #expect(card.title == "title w1:p2")
        #expect(card.kind == .needsInput)
        #expect(card.key == .herdr("w1:p2"))
    }

    @Test func metaNamesTheProjectFromTheRoster() {
        let finished = alert("w1:p1", .finished, minute: 2)
        let card = Content.cards(for: [finished], roster: [entry("w1:p1", cwd: "/Users/m/Work/api")], timeZone: utc)[0]
        #expect(card.meta == "done · api · 16:02")
    }

    @Test func metaLeavesOutTheProjectOfAnAgentNoLongerListed() {
        let finished = alert("w1:p1", .finished, minute: 2)
        let card = Content.cards(for: [finished], roster: [entry("w1:p9", cwd: "/x/api")], timeZone: utc)[0]
        #expect(card.meta == "done · 16:02")
    }

    @Test func blankPreviewShowsNone() {
        let cards = Content.cards(for: [alert("w1:p1", .finished, minute: 2, preview: " \n ")], roster: [], timeZone: utc)
        #expect(cards[0].preview == nil)
    }

    @Test func previewIsTrimmed() {
        let cards = Content.cards(for: [alert("w1:p1", .finished, minute: 2, preview: "\n All tests pass.\n")],
                                  roster: [], timeZone: utc)
        #expect(cards[0].preview == "All tests pass.")
    }
}
