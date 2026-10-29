import AppKit

/// The menu-bar menu as plain values, so its contents can be checked without a status bar.
struct ShellMenu {
    struct State {
        var isHUDVisible: Bool
        var isLaunchAtLoginOn: Bool
        var launchAtLoginError: String?
        var version: String
        var unavailableShortcuts: [ShellHotKey]
    }

    struct Item {
        var title: String
        /// Items without a command are informational and shown disabled.
        var command: ShellCommand?
        var keyEquivalent = ""
        var keyModifiers: NSEvent.ModifierFlags = []
        var isChecked = false

        var isEnabled: Bool { command != nil }
    }

    enum Entry {
        case item(Item)
        case separator
    }

    let entries: [Entry]

    init(state: State) {
        var entries: [Entry] = [
            .item(Item(title: "Open agents panel", command: .openPanel, hotKey: .togglePanel)),
            .item(Item(title: state.isHUDVisible ? "Hide HUD" : "Show HUD", command: .toggleHUD, hotKey: .toggleHUD)),
        ]
        entries += state.unavailableShortcuts.map { .item(Item(title: "Shortcut \($0.symbol) unavailable")) }
        entries += [
            .separator,
            .item(Item(title: "Refresh agents", command: .refresh)),
            .item(Item(title: "Launch at login", command: .toggleLaunchAtLogin, isChecked: state.isLaunchAtLoginOn)),
        ]
        if let error = state.launchAtLoginError {
            entries.append(.item(Item(title: error)))
        }
        entries += [
            .separator,
            .item(Item(title: "agents hud \(state.version)")),
            .item(Item(title: "Quit Agents HUD", command: .quit, keyEquivalent: "q", keyModifiers: [.command])),
        ]
        self.entries = entries
    }

    static func statusTitle(badgeCount: Int) -> String {
        badgeCount > 0 ? "H · \(badgeCount)" : "H"
    }

    static func version(from infoDictionary: [String: Any]?) -> String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

private extension ShellMenu.Item {
    init(title: String, command: ShellCommand, hotKey: ShellHotKey) {
        self.init(title: title, command: command, keyEquivalent: hotKey.keyEquivalent, keyModifiers: hotKey.keyModifiers)
    }
}
