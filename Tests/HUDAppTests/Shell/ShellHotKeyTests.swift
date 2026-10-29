import AppKit
import Carbon
import Testing
@testable import HUDApp

@Suite struct ShellHotKeyTests {
    @MainActor private final class FakeRegistrar: ShellHotKeyRegistering {
        var refused: Set<ShellHotKey> = []
        var registered: [ShellHotKey] = []
        var presses: [ShellHotKey: @MainActor () -> Void] = [:]

        func register(_ hotKey: ShellHotKey, onPress: @escaping @MainActor () -> Void) -> Bool {
            registered.append(hotKey)
            guard !refused.contains(hotKey) else { return false }
            presses[hotKey] = onPress
            return true
        }
    }

    private let hyper = UInt32(cmdKey | controlKey | optionKey)

    @Test func hyperHTogglesThePanel() {
        let hotKey = ShellHotKey.togglePanel
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_H))
        #expect(hotKey.carbonModifiers == hyper)
        #expect(hotKey.command == .togglePanel)
        #expect(hotKey.symbol == "⌃⌥⌘H")
        #expect(hotKey.keyEquivalent == "h")
        #expect(hotKey.keyModifiers == [.command, .control, .option])
    }

    @Test func hyperShiftHTogglesTheHUD() {
        let hotKey = ShellHotKey.toggleHUD
        #expect(hotKey.keyCode == UInt32(kVK_ANSI_H))
        #expect(hotKey.carbonModifiers == hyper | UInt32(shiftKey))
        #expect(hotKey.command == .toggleHUD)
        #expect(hotKey.symbol == "⇧⌃⌥⌘H")
        #expect(hotKey.keyEquivalent == "h")
        #expect(hotKey.keyModifiers == [.command, .control, .option, .shift])
    }

    @Test func hotKeysHaveDistinctIDs() {
        #expect(Set(ShellHotKey.all.map(\.id)).count == ShellHotKey.all.count)
        #expect(ShellHotKey.all == [.togglePanel, .toggleHUD])
    }

    @Test @MainActor func registersEveryHotKeyAndRoutesPressesToTheirCommands() {
        let registrar = FakeRegistrar()
        var performed: [ShellCommand] = []

        let unavailable = ShellHotKey.registerAll(with: registrar) { performed.append($0) }

        #expect(unavailable.isEmpty)
        #expect(registrar.registered == ShellHotKey.all)
        registrar.presses[.toggleHUD]?()
        registrar.presses[.togglePanel]?()
        #expect(performed == [.toggleHUD, .togglePanel])
    }

    @Test @MainActor func reportsRefusedHotKeysAndKeepsTheRest() {
        let registrar = FakeRegistrar()
        registrar.refused = [.togglePanel]
        var performed: [ShellCommand] = []

        let unavailable = ShellHotKey.registerAll(with: registrar) { performed.append($0) }

        #expect(unavailable == [.togglePanel])
        #expect(registrar.registered == ShellHotKey.all)
        registrar.presses[.toggleHUD]?()
        #expect(performed == [.toggleHUD])
    }
}
