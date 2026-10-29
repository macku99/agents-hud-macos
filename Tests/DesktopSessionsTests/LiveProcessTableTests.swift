import Darwin
import Foundation
import Testing
@testable import DesktopSessions

@Suite struct LiveProcessTableTests {
    @Test func readsThisProcesssParent() {
        #expect(LiveProcessTable().parent(of: getpid()) == getppid())
    }

    @Test func readsThisProcesssStartInClaudeCodesFormat() throws {
        let start = try #require(LiveProcessTable().startTime(of: getpid()))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let started = try #require(formatter.date(from: start.split(separator: " ").joined(separator: " ")))

        #expect(started <= Date())
        #expect(started > Date().addingTimeInterval(-3600))
    }

    @Test func aProcessThatDoesNotExistHasNoStart() {
        #expect(LiveProcessTable().startTime(of: 999_999) == nil)
        #expect(LiveProcessTable().parent(of: 999_999) == nil)
    }
}
