import Foundation
import Testing
@testable import HUDApp

@Suite struct PanelTimeTextTests {
    private let text = PanelController.TimeText(timeZone: TimeZone(identifier: "UTC")!)
    private let base = Date(timeIntervalSince1970: 1_800_000_000) // 08:00:00 UTC

    @Test func clockShowsHoursWithoutPaddingAndMinutesPadded() {
        #expect(text.clock(base) == "8:00")
        #expect(text.clock(base.addingTimeInterval(8 * 3600 + 2 * 60 + 59)) == "16:02")
    }

    @Test func clockUsesTheGivenTimeZone() {
        let berlin = PanelController.TimeText(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        #expect(berlin.clock(base) == "9:00")
    }

    @Test func timerShowsMinutesAndSecondsUnderAnHour() {
        #expect(text.timer(from: base, to: base.addingTimeInterval(192.9)) == "3:12")
        #expect(text.timer(from: base, to: base.addingTimeInterval(5)) == "0:05")
    }

    @Test func timerShowsHoursFromAnHourOn() {
        #expect(text.timer(from: base, to: base.addingTimeInterval(3600 + 62)) == "1:01:02")
    }

    @Test func timerNeverRunsBackwards() {
        #expect(text.timer(from: base, to: base.addingTimeInterval(-30)) == "0:00")
    }

    @Test func durationIsShortAndReadable() {
        #expect(text.duration(.seconds(33)) == "33s")
        #expect(text.duration(.milliseconds(400)) == "0s")
        #expect(text.duration(.seconds(125)) == "2m 5s")
        #expect(text.duration(.seconds(3 * 3600 + 7 * 60 + 9)) == "3h 7m")
    }
}
