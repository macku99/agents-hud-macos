import Foundation
import Testing
@testable import HUDApp

@Suite struct PanelRosterWidthTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "PanelRosterWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func clampsToTheAllowedRange() {
        #expect(PanelController.RosterWidth.clamped(100) == 220)
        #expect(PanelController.RosterWidth.clamped(350) == 350)
        #expect(PanelController.RosterWidth.clamped(900) == 480)
    }

    @Test func startsAtTheDefaultWidth() {
        withDefaults { defaults in
            #expect(PanelController.RosterWidth(defaults: defaults).stored == 300)
        }
    }

    @Test func remembersTheWidth() {
        withDefaults { defaults in
            PanelController.RosterWidth(defaults: defaults).store(360)
            #expect(PanelController.RosterWidth(defaults: defaults).stored == 360)
        }
    }

    @Test func storesTheClampedWidth() {
        withDefaults { defaults in
            let width = PanelController.RosterWidth(defaults: defaults)
            width.store(600)
            #expect(width.stored == 480)
        }
    }

    @Test func clampsAStoredWidthOutsideTheRange() {
        withDefaults { defaults in
            defaults.set(40.0, forKey: PanelController.RosterWidth.key)
            #expect(PanelController.RosterWidth(defaults: defaults).stored == 220)
        }
    }
}
