import AppKit

extension OverlayController {
    /// A borderless panel that floats above every app, including fullscreen Spaces, on every Space,
    /// and never takes focus from the app the user is in.
    final class FloatingPanel: NSPanel {
        init(contentRect: CGRect) {
            super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                       defer: true)
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            isMovable = false
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
        }

        override var canBecomeMain: Bool { false }
        override var canBecomeKey: Bool { false }
    }
}
