import ServiceManagement

@MainActor
protocol ShellLoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

/// The "Launch at login" switch. A failed toggle is kept as text for the menu, never shown as a dialog.
@MainActor
final class ShellLoginItem {
    struct SystemService: ShellLoginItemService {
        var status: SMAppService.Status { SMAppService.mainApp.status }
        func register() throws { try SMAppService.mainApp.register() }
        func unregister() throws { try SMAppService.mainApp.unregister() }
    }

    private let service: any ShellLoginItemService
    private(set) var error: String?

    init(service: any ShellLoginItemService) {
        self.service = service
    }

    var isOn: Bool { Self.isOn(service.status) }

    /// Awaiting approval counts as off: the app does not launch at login until M approves it in
    /// System Settings.
    nonisolated static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled
    }

    func toggle() {
        do {
            if isOn {
                try service.unregister()
            } else {
                try service.register()
            }
            error = nil
        } catch {
            self.error = "Launch at login failed: \(error.localizedDescription)"
        }
    }
}
