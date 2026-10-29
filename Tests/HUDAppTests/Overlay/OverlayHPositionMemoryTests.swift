import AppKit
import Foundation
import Testing
@testable import HUDApp

@Suite struct OverlayHPositionMemoryTests {
    typealias Memory = OverlayController.HPositionMemory

    /// A suite named by an absolute path keeps its plist in a temp directory instead of
    /// ~/Library/Preferences.
    private func withSuite(_ body: (UserDefaults) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "overlay-defaults-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = directory.appending(path: "suite").path
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        body(defaults)
    }

    @Test func displayKeyIsTheScreenNumber() {
        let description: [NSDeviceDescriptionKey: Any] = [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: 69_733_382)]
        #expect(Memory.displayID(from: description) == 69_733_382)
    }

    @Test func displayKeyIsMissingWithoutAScreenNumber() {
        #expect(Memory.displayID(from: [:]) == nil)
        #expect(Memory.displayID(from: [NSDeviceDescriptionKey("NSScreenNumber"): "1"]) == nil)
    }

    @Test func savedOffsetsRoundTripPerDisplay() throws {
        try withSuite { defaults in
            let memory = Memory(defaults: defaults)
            memory.save(offset: CGPoint(x: 12.5, y: 300), on: 7)
            memory.save(offset: CGPoint(x: 40, y: 2), on: 9)

            let reread = Memory(defaults: defaults)
            #expect(reread.offset(on: 7) == CGPoint(x: 12.5, y: 300))
            #expect(reread.offset(on: 9) == CGPoint(x: 40, y: 2))
            #expect(reread.offset(on: 8) == nil)
        }
    }

    @Test func savingRemembersTheLastDisplay() throws {
        try withSuite { defaults in
            let memory = Memory(defaults: defaults)
            #expect(memory.lastDisplay == nil)
            memory.save(offset: .zero, on: 7)
            memory.save(offset: .zero, on: 9)
            #expect(Memory(defaults: defaults).lastDisplay == 9)
        }
    }

    @Test func savingAgainReplacesTheOffset() throws {
        try withSuite { defaults in
            let memory = Memory(defaults: defaults)
            memory.save(offset: CGPoint(x: 1, y: 1), on: 7)
            memory.save(offset: CGPoint(x: 2, y: 3), on: 7)
            #expect(memory.offset(on: 7) == CGPoint(x: 2, y: 3))
        }
    }
}
