import AppKit
import Testing
@testable import HUDApp

@Suite struct ShellMenuTests {
    private func menu(
        isHUDVisible: Bool = true,
        isLaunchAtLoginOn: Bool = false,
        launchAtLoginError: String? = nil,
        version: String = "1.2.0",
        unavailableShortcuts: [ShellHotKey] = []
    ) -> ShellMenu {
        ShellMenu(state: .init(
            isHUDVisible: isHUDVisible,
            isLaunchAtLoginOn: isLaunchAtLoginOn,
            launchAtLoginError: launchAtLoginError,
            version: version,
            unavailableShortcuts: unavailableShortcuts
        ))
    }

    private func titles(_ menu: ShellMenu) -> [String] {
        menu.entries.map {
            switch $0 {
            case .separator: "---"
            case .item(let item): item.title
            }
        }
    }

    private func item(_ title: String, in menu: ShellMenu) -> ShellMenu.Item? {
        for case .item(let item) in menu.entries where item.title == title { return item }
        return nil
    }

    @Test func listsItemsInOrderWithSeparators() {
        #expect(titles(menu()) == [
            "Open agents panel",
            "Hide HUD",
            "---",
            "Refresh agents",
            "Launch at login",
            "---",
            "agents hud 1.2.0",
            "Quit Agents HUD",
        ])
    }

    @Test func hudItemFollowsVisibility() {
        #expect(item("Hide HUD", in: menu(isHUDVisible: true))?.command == .toggleHUD)
        #expect(item("Show HUD", in: menu(isHUDVisible: false))?.command == .toggleHUD)
        #expect(item("Hide HUD", in: menu(isHUDVisible: false)) == nil)
    }

    @Test func actionItemsCarryCommands() {
        let menu = menu()
        #expect(item("Open agents panel", in: menu)?.command == .openPanel)
        #expect(item("Refresh agents", in: menu)?.command == .refresh)
        #expect(item("Launch at login", in: menu)?.command == .toggleLaunchAtLogin)
        #expect(item("Quit Agents HUD", in: menu)?.command == .quit)
    }

    @Test func keyEquivalentsMatchTheShortcuts() {
        let menu = menu()
        let hyper: NSEvent.ModifierFlags = [.command, .control, .option]
        let open = item("Open agents panel", in: menu)
        #expect(open?.keyEquivalent == "h")
        #expect(open?.keyModifiers == hyper)
        let hud = item("Hide HUD", in: menu)
        #expect(hud?.keyEquivalent == "h")
        #expect(hud?.keyModifiers == hyper.union(.shift))
        let quit = item("Quit Agents HUD", in: menu)
        #expect(quit?.keyEquivalent == "q")
        #expect(quit?.keyModifiers == [.command])
        #expect(item("Refresh agents", in: menu)?.keyEquivalent == "")
        #expect(item("Launch at login", in: menu)?.keyEquivalent == "")
    }

    @Test func launchAtLoginIsCheckedOnlyWhenOn() {
        #expect(item("Launch at login", in: menu(isLaunchAtLoginOn: true))?.isChecked == true)
        #expect(item("Launch at login", in: menu(isLaunchAtLoginOn: false))?.isChecked == false)
        #expect(item("Refresh agents", in: menu(isLaunchAtLoginOn: true))?.isChecked == false)
    }

    @Test func versionLineIsDisabledAndCommandless() {
        let version = item("agents hud 1.2.0", in: menu())
        #expect(version?.isEnabled == false)
        #expect(version?.command == nil)
    }

    @Test func actionItemsAreEnabled() {
        let menu = menu()
        for title in ["Open agents panel", "Hide HUD", "Refresh agents", "Launch at login", "Quit Agents HUD"] {
            #expect(item(title, in: menu)?.isEnabled == true, "\(title)")
        }
    }

    @Test func loginErrorShowsAsDisabledItemAfterLaunchAtLogin() {
        let menu = menu(launchAtLoginError: "Launch at login failed: no bundle")
        let titles = titles(menu)
        let toggle = titles.firstIndex(of: "Launch at login")
        #expect(toggle.map { titles[$0 + 1] } == "Launch at login failed: no bundle")
        let error = item("Launch at login failed: no bundle", in: menu)
        #expect(error?.isEnabled == false)
        #expect(error?.command == nil)
    }

    @Test func unavailableShortcutsShowAsDisabledItemsAfterTheHUDItem() {
        let menu = menu(unavailableShortcuts: [.togglePanel, .toggleHUD])
        #expect(Array(titles(menu).prefix(5)) == [
            "Open agents panel",
            "Hide HUD",
            "Shortcut ⌃⌥⌘H unavailable",
            "Shortcut ⇧⌃⌥⌘H unavailable",
            "---",
        ])
        for title in ["Shortcut ⌃⌥⌘H unavailable", "Shortcut ⇧⌃⌥⌘H unavailable"] {
            #expect(item(title, in: menu)?.isEnabled == false)
            #expect(item(title, in: menu)?.command == nil)
        }
    }

    @Test func statusTitleShowsBadgeCountOnlyWhenPositive() {
        #expect(ShellMenu.statusTitle(badgeCount: 0) == "H")
        #expect(ShellMenu.statusTitle(badgeCount: -1) == "H")
        #expect(ShellMenu.statusTitle(badgeCount: 1) == "H · 1")
        #expect(ShellMenu.statusTitle(badgeCount: 12) == "H · 12")
    }

    @Test func versionComesFromShortVersionStringOrFallsBackToDev() {
        #expect(ShellMenu.version(from: ["CFBundleShortVersionString": "0.3.1"]) == "0.3.1")
        #expect(ShellMenu.version(from: ["CFBundleVersion": "7"]) == "dev")
        #expect(ShellMenu.version(from: ["CFBundleShortVersionString": 3]) == "dev")
        #expect(ShellMenu.version(from: nil) == "dev")
    }
}
