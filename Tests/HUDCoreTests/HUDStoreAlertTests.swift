import Foundation
import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@Suite @MainActor struct HUDStoreAlertTests {
    @Test func theFirstRosterAfterStartRaisesNoAlerts() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "w1:p1", status: .blocked),
            .fake(pane: "w1:p2", status: .done, completionSeq: 1),
        ])
        await harness.store.start()
        defer { harness.store.stop() }

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func theFirstRosterAfterARestartRaisesNoAlerts() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        await harness.store.start()
        harness.store.stop()
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .blocked)])

        await harness.store.start()
        defer { harness.store.stop() }

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func becomingBlockedRaisesANeedsInputAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working, title: "Fix login")])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.advance(by: 60)

        await harness.reload([.fake(pane: "w1:p1", status: .blocked, title: "Fix login")])

        let alert = harness.store.alerts.first
        #expect(harness.store.alerts.count == 1)
        #expect(alert?.key == harness.key("w1:p1"))
        #expect(alert?.kind == .needsInput)
        #expect(alert?.title == "Fix login")
        #expect(alert?.preview == "")
        #expect(alert?.at == harness.now)
    }

    @Test func finishingWorkRaisesAFinishedAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working, title: "Refactor")])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1", status: .done, title: "Refactor", completionSeq: 1)])

        #expect(harness.store.alerts.map(\.kind) == [.finished])
        #expect(harness.store.alerts.first?.title == "Refactor")
    }

    @Test func aNewCompletionWhileDoneRaisesAFinishedAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 1)])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 2)])

        #expect(harness.store.alerts.map(\.kind) == [.finished])
    }

    @Test func agentsThatAreNotNewlyBlockedOrFinishedRaiseNoAlerts() async {
        let agents: [AgentInfo] = [
            .fake(pane: "blocked", status: .blocked),
            .fake(pane: "done", status: .done, completionSeq: 1),
            .fake(pane: "working", status: .working),
        ]
        let harness = HUDStoreHarness(agents: agents)
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload(agents)
        await harness.reload([
            .fake(pane: "blocked", status: .blocked),
            .fake(pane: "done", status: .idle, completionSeq: 1),
            .fake(pane: "working", status: .idle),
        ])

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func anAgentFirstSeenAfterStartRaisesNoAlert() async {
        let harness = HUDStoreHarness()
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1", status: .blocked)])

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func aNewAgentInAReusedPaneRaisesNoAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }

        await harness.reload([.fake(pane: "w1:p1", status: .blocked, agent: "codex")])

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func aReusedPaneDropsTheOldAgentsAlerts() async {
        let harness = HUDStoreHarness(agents: [
            .fake(pane: "w1:p1", status: .working, title: "Old task"),
            .fake(pane: "w1:p2", status: .working, title: "Old build"),
        ])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([
            .fake(pane: "w1:p1", status: .blocked, title: "Old task"),
            .fake(pane: "w1:p2", status: .done, title: "Old build", completionSeq: 1),
        ])
        #expect(harness.store.alerts.count == 2)

        await harness.reload([
            .fake(pane: "w1:p1", status: .blocked, title: "New task", agent: "codex"),
            .fake(pane: "w1:p2", status: .idle, title: "New build", agent: "codex"),
        ])
        #expect(harness.store.alerts.isEmpty)

        await harness.reload([
            .fake(pane: "w1:p1", status: .blocked, title: "New task", agent: "codex"),
            .fake(pane: "w1:p2", status: .blocked, title: "New build", agent: "codex"),
        ])
        #expect(harness.store.alerts.map(\.title) == ["New build"])
    }

    @Test func noAlertsWhileThePanelIsOpen() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.openPanel()

        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .done, completionSeq: 1)])

        #expect(harness.store.alerts.isEmpty)
    }

    @Test func theFirstRosterAfterTheHUDIsShownAgainRaisesNoAlerts() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.store.toggleHUD()
        harness.herdr.setAgents([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .working)])

        harness.store.toggleHUD()
        await harness.waitUntil("the roster reloads") { harness.entry("w1:p1")?.agent.status == .blocked }
        #expect(harness.store.alerts.isEmpty)

        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .blocked)])
        #expect(harness.store.alerts.map(\.key) == [harness.key("w1:p2")])
    }

    @Test func aHiddenHUDRaisesNoAlertsAndDropsThoseItHad() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .working)])
        #expect(harness.store.alerts.count == 1)

        harness.store.toggleHUD()
        #expect(harness.store.alerts.isEmpty)
        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .blocked)])
        #expect(harness.store.alerts.isEmpty)
    }

    @Test func aChangeFoundWhenHerdrAnswersAgainRaisesAnAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        harness.herdr.failNext(.agents, with: .unreachable("gone"))
        await harness.store.refresh()

        await harness.reload([.fake(pane: "w1:p1", status: .blocked)])

        #expect(harness.store.alerts.map(\.kind) == [.needsInput])
    }

    @Test func aNeedsInputAlertGoesOnceTheAgentIsNoLongerBlocked() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .blocked)])
        #expect(harness.store.alerts.count == 2)

        await harness.reload([.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .blocked)])
        #expect(harness.store.alerts.map(\.key) == [harness.key("w1:p2")])

        await harness.reload([])
        #expect(harness.store.alerts.isEmpty)
    }

    @Test func aBlockedAgentThatFinishesSwapsItsAlert() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .blocked)])

        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 1)])

        #expect(harness.store.alerts.map(\.kind) == [.finished])
    }

    @Test func onlyTheNewestAlertPerPaneAndKindIsKept() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .done, completionSeq: 1), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 2), .fake(pane: "w1:p2", status: .working)])
        harness.advance(by: 60)

        await harness.reload([.fake(pane: "w1:p1", status: .done, completionSeq: 3), .fake(pane: "w1:p2", status: .done, completionSeq: 1)])

        #expect(harness.store.alerts.map(\.key) == [harness.key("w1:p1"), harness.key("w1:p2")])
        #expect(harness.store.alerts.first?.at == harness.now)
    }

    @Test func dismissingRemovesOnlyThatAlert() async throws {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .blocked)])
        let first = try #require(harness.store.alerts.first)

        harness.store.dismissAlert(first.id)

        #expect(harness.store.alerts.map(\.key) == [harness.key("w1:p2")])
    }

    @Test func openingThePanelClearsAllAlerts() async {
        let harness = HUDStoreHarness(agents: [.fake(pane: "w1:p1", status: .working), .fake(pane: "w1:p2", status: .working)])
        await harness.store.start()
        defer { harness.store.stop() }
        await harness.reload([.fake(pane: "w1:p1", status: .blocked), .fake(pane: "w1:p2", status: .blocked)])
        #expect(harness.store.alerts.count == 2)

        harness.store.openPanel()

        #expect(harness.store.alerts.isEmpty)
    }
}
