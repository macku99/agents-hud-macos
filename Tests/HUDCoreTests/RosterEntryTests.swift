import Testing
import HerdrKit
import HerdrKitTesting
@testable import HUDCore

@MainActor
@Test func rosterEntryIsIdentifiedByItsAgentKey() {
    let harness = HUDStoreHarness()
    let entry = RosterEntry(agent: harness.snapshot(of: .fake(pane: "w4:p2")), attention: .none, stateSince: nil)
    #expect(entry.id == harness.key("w4:p2"))
}
