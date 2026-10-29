import AppKit
import HUDCore
import Observation

/// Owns the menu-bar menu, the global shortcuts and the login item.
@MainActor
public final class ShellController: NSObject, NSMenuDelegate {
    private let store: HUDStore
    private let loginItem = ShellLoginItem(service: ShellLoginItem.SystemService())
    private let hotKeyRegistrar = ShellHotKey.SystemRegistrar()
    private let version = ShellMenu.version(from: Bundle.main.infoDictionary)
    private var statusItem: NSStatusItem?
    private var unavailableShortcuts: [ShellHotKey] = []
    private var storeObservation: Task<Void, Never>?

    public init(store: HUDStore) {
        self.store = store
    }

    public func start() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        self.statusItem = statusItem

        unavailableShortcuts = ShellHotKey.registerAll(with: hotKeyRegistrar) { [weak self] in
            self?.perform($0)
        }
        render()

        // The menu itself is rebuilt each time it opens; between openings only the badge shows.
        storeObservation = Task { [weak self, store] in
            for await _ in Observations({ store.badgeCount }) {
                guard let self else { return }
                self.renderStatusTitle()
            }
        }
    }

    /// The login item's status lives in the system and can change in System Settings, so it is
    /// re-read every time the menu opens.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        render()
    }

    private func renderStatusTitle() {
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: ShellMenu.statusTitle(badgeCount: store.badgeCount),
            attributes: [.font: Self.statusFont]
        )
    }

    private func render() {
        guard let statusItem else { return }
        renderStatusTitle()
        let model = ShellMenu(state: .init(
            isHUDVisible: store.isHUDVisible,
            isLaunchAtLoginOn: loginItem.isOn,
            launchAtLoginError: loginItem.error,
            version: version,
            unavailableShortcuts: unavailableShortcuts
        ))
        statusItem.menu?.items = model.entries.map(menuItem)
    }

    private func menuItem(for entry: ShellMenu.Entry) -> NSMenuItem {
        guard case .item(let item) = entry else { return .separator() }
        let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.keyEquivalent)
        menuItem.keyEquivalentModifierMask = item.keyModifiers
        menuItem.isEnabled = item.isEnabled
        menuItem.state = item.isChecked ? .on : .off
        if let command = item.command {
            menuItem.target = self
            menuItem.action = #selector(performMenuItem(_:))
            menuItem.tag = command.rawValue
        }
        return menuItem
    }

    @objc private func performMenuItem(_ sender: NSMenuItem) {
        guard let command = ShellCommand(rawValue: sender.tag) else { return }
        perform(command)
    }

    private func perform(_ command: ShellCommand) {
        switch command {
        case .openPanel:
            store.openPanel()
        case .togglePanel:
            store.togglePanel()
        case .toggleHUD:
            store.toggleHUD()
        case .refresh:
            Task { await store.refresh() }
        case .toggleLaunchAtLogin:
            loginItem.toggle()
            render()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private static let statusFont: NSFont = {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSFont(name: "GeistMono-SemiBold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .semibold)
    }()
}
