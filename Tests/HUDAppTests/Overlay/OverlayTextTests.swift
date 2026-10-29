import Foundation
import HUDCore
import Testing
@testable import HUDApp

@Suite struct OverlayTextTests {
    typealias Text = OverlayController.OverlayText

    @Test func noBadgeAtZeroOrBelow() {
        #expect(Text.badge(count: 0) == nil)
        #expect(Text.badge(count: -1) == nil)
    }

    @Test func badgeShowsTheCountUpToNine() {
        #expect(Text.badge(count: 1) == "1")
        #expect(Text.badge(count: 9) == "9")
    }

    @Test func badgeCapsAtNinePlus() {
        #expect(Text.badge(count: 10) == "9+")
        #expect(Text.badge(count: 120) == "9+")
    }

    @Test func projectIsTheLastPathComponentOfTheWorkingDirectory() {
        #expect(Text.project(cwd: "/Users/m/Work/herdr-hud") == "herdr-hud")
        #expect(Text.project(cwd: "/Users/m/Work/herdr-hud/") == "herdr-hud")
        #expect(Text.project(cwd: nil) == nil)
        #expect(Text.project(cwd: "") == nil)
        #expect(Text.project(cwd: "/") == nil)
    }

    private let utc = TimeZone(identifier: "UTC")!
    private let at = Date(timeIntervalSince1970: 16 * 3600 + 2 * 60 + 30)

    @Test func finishedAlertMetaNamesStateProjectAndTime() {
        #expect(Text.alertMeta(kind: .finished, project: "herdr-hud", at: at, timeZone: utc) == "done · herdr-hud · 16:02")
    }

    @Test func needsInputAlertMetaNamesStateProjectAndTime() {
        #expect(Text.alertMeta(kind: .needsInput, project: "api", at: at, timeZone: utc) == "needs input · api · 16:02")
    }

    @Test func alertMetaLeavesOutAnUnknownProject() {
        #expect(Text.alertMeta(kind: .finished, project: nil, at: at, timeZone: utc) == "done · 16:02")
    }

    @Test func alertTimePadsHoursAndMinutes() {
        let early = Date(timeIntervalSince1970: 7 * 3600 + 5 * 60)
        #expect(Text.alertMeta(kind: .finished, project: nil, at: early, timeZone: utc) == "done · 07:05")
    }
}
