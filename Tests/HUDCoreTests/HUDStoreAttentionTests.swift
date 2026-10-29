import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreAttentionTests {
    @Test func viewingAFinishedTurnClearsItUntilTheNextCompletion() async {
        let other = AgentInfo.fake(pane: "w1:p0", status: .done, completionSeq: 1)
        let harness = HUDStoreHarness(agents: [other, .fake(pane: "w1:p1", status: .done, completionSeq: 3)])
        await harness.store.start()
        defer { harness.store.stop() }
        #expect(harness.entry("w1:p1")?.attention == .unseen)

        harness.store.openPanel()
        harness.store.select(harness.key("w1:p1"))
        #expect(harness.entry("w1:p1")?.attention == Attention.none)
        #expect(harness.store.badgeCount == 0)

        harness.store.togglePanel()
        await harness.reload([other, .fake(pane: "w1:p1", status: .done, completionSeq: 3)])
        #expect(harness.entry("w1:p1")?.attention == Attention.none)
        await harness.reload([other, .fake(pane: "w1:p1", status: .done, completionSeq: 4)])
        #expect(harness.entry("w1:p1")?.attention == .unseen)
        #expect(harness.store.badgeCount == 1)
    }

    @Test func withoutACompletionSeqTheStateChangeSeqMarksTheFinish() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: nil, stateChangeSeq: 5)])
        await harness.store.start()
        defer { harness.store.stop() }
        #expect(harness.entry("w1:p1")?.attention == .unseen)

        harness.store.openPanel(on: harness.key("w1:p1"))
        harness.store.togglePanel()
        #expect(harness.entry("w1:p1")?.attention == Attention.none)

        await harness.reload([.fake(pane: "w1:p1", status: .working, completionSeq: nil, stateChangeSeq: 6)])
        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: nil, stateChangeSeq: 7)])
        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }

    @Test func aCompletionSeqAfterAViewedStateChangeSeqCountsAsANewFinish() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: nil, stateChangeSeq: 9)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.openPanel(on: harness.key("w1:p1"))
        harness.store.togglePanel()

        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 2, stateChangeSeq: 9)])

        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }

    @Test func selectingWithThePanelClosedIsNotViewing() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 3)])
        await harness.store.start()
        defer { harness.store.stop() }

        harness.store.select(harness.key("w1:p1"))

        #expect(harness.store.selectedAgent == harness.key("w1:p1"))
        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }

    @Test func openingThePanelViewsTheAgentAlreadySelected() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "w1:p1", status: .done, completionSeq: 1),
            .fake(pane: "w1:p2", status: .done, completionSeq: 1),
        ])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.select(harness.key("w1:p2"))

        harness.store.openPanel()

        #expect(harness.entry("w1:p2")?.attention == Attention.none)
        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }

    @Test func openingThePanelWithNothingSelectedSelectsAndViewsTheFirstAgent() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "w1:p1", status: .idle),
            .fake(pane: "w1:p2", status: .done, completionSeq: 1),
        ])
        await harness.store.start()
        defer { harness.store.stop() }

        harness.store.openPanel()

        #expect(harness.store.selectedAgent == harness.key("w1:p2"))
        #expect(harness.entry("w1:p2")?.attention == Attention.none)
    }

    @Test func theSelectedAgentFinishingWhileThePanelIsOpenIsViewed() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working, completionSeq: 1)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.openPanel()

        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 2)])

        #expect(harness.entry("w1:p1")?.attention == Attention.none)
    }

    @Test func focusingInHerdrTurnsDoneIntoIdleWhichClearsIt() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 3)])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1", status: .idle, completionSeq: 3)])

        #expect(harness.entry("w1:p1")?.attention == Attention.none)
        #expect(harness.store.badgeCount == 0)
    }

    @Test func aNewAgentInAViewedPaneStartsUnseen() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 3)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.openPanel(on: harness.key("w1:p1"))
        harness.store.togglePanel()

        await harness.reload([.fake(pane: "w1:p1", status: .done, agent: "codex", completionSeq: 3)])

        #expect(harness.entry("w1:p1")?.attention == .unseen)
    }
}
