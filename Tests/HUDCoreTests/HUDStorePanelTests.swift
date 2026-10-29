import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStorePanelTests {
    @Test func togglePanelOpensAndCloses() {
        let harness = HUDStoreHarness()
        harness.store.togglePanel()
        #expect(harness.store.isPanelOpen)
        harness.store.togglePanel()
        #expect(!harness.store.isPanelOpen)
    }

    @Test func openPanelOnAPaneSelectsIt() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])
        await harness.store.start()
        defer { harness.store.stop() }

        harness.store.openPanel(on: harness.key("w1:p2"))

        #expect(harness.store.isPanelOpen)
        #expect(harness.store.selectedAgent == harness.key("w1:p2"))
    }

    @Test func openingThePanelKeepsAnExistingSelection() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.select(harness.key("w1:p2"))

        harness.store.openPanel()

        #expect(harness.store.selectedAgent == harness.key("w1:p2"))
    }

    @Test func hidingTheHUDClosesThePanel() {
        let harness = HUDStoreHarness()
        harness.store.openPanel()

        harness.store.toggleHUD()

        #expect(!harness.store.isHUDVisible)
        #expect(!harness.store.isPanelOpen)
    }

    @Test func showingTheHUDAgainReloadsTheRoster() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1")])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.toggleHUD()
        harness.herdr.setAgents([.fake(pane: "w1:p1"), .fake(pane: "w1:p2")])

        harness.store.toggleHUD()

        #expect(harness.store.isHUDVisible)
        await harness.waitUntil("the roster reloads") { harness.store.roster.count == 2 }
    }

    @Test func openingThePanelWhileTheHUDIsHiddenShowsTheHUD() {
        let harness = HUDStoreHarness()
        harness.store.toggleHUD()

        harness.store.togglePanel()

        #expect(harness.store.isPanelOpen)
        #expect(harness.store.isHUDVisible)
    }
}
