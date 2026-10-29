import Foundation
import Testing
import Transcript
@testable import HUDApp

@Suite struct PanelChatTests {
    private let time = PanelController.TimeText(timeZone: TimeZone(identifier: "UTC")!)

    @Test func toolGroupsStartCollapsed() {
        #expect(!PanelController.ToolGroupExpansion().isExpanded("b1"))
    }

    @Test func togglingExpandsAndCollapsesOneGroup() {
        var expansion = PanelController.ToolGroupExpansion()
        expansion.toggle("b1")
        #expect(expansion.isExpanded("b1"))
        #expect(!expansion.isExpanded("b2"))
        expansion.toggle("b1")
        #expect(!expansion.isExpanded("b1"))
    }

    @Test func expansionSurvivesARereadOfTheTranscript() {
        let tools = ChatBlock.Kind.tools(summary: "read 2 files", calls: [])
        var expansion = PanelController.ToolGroupExpansion()
        expansion.toggle(ChatBlock(id: "b7", kind: tools, at: nil).id)

        let reread = [ChatBlock(id: "b8", kind: .prompt("next"), at: nil), ChatBlock(id: "b7", kind: tools, at: nil)]
        #expect(reread.map { expansion.isExpanded($0.id) } == [false, true])
    }

    @Test func turnMetaSaysHowLongItWorkedAndWhenItEnded() {
        let at = Date(timeIntervalSince1970: 1_800_000_000 + 7 * 3600 + 55 * 60) // 15:55 UTC
        #expect(PanelController.ChatText.turnMeta(duration: .seconds(33), at: at, time: time) == "worked for 33s · 15:55")
    }

    @Test func turnMetaWithoutATimestampShowsOnlyTheDuration() {
        #expect(PanelController.ChatText.turnMeta(duration: .seconds(125), at: nil, time: time) == "worked for 2m 5s")
    }
}
