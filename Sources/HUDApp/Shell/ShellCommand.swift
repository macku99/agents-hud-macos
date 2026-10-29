/// Everything the menu-bar menu and the global shortcuts can ask the app to do.
enum ShellCommand: Int, Hashable, Sendable {
    case openPanel
    case togglePanel
    case toggleHUD
    case refresh
    case toggleLaunchAtLogin
    case quit
}
