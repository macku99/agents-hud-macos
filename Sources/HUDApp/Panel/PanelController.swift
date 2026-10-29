import AppKit
import DesktopSessions
import Foundation
import HUDCore
import SwiftUI
import Transcript

/// Owns the agent panel that opens beside H. It shows and hides itself by observing
/// `HUDStore.isPanelOpen`; nothing else orders the panel window.
@MainActor
public final class PanelController {
    private let store: HUDStore
    private let anchor: HAnchor
    private let transcripts: any TranscriptSource
    private let jump: AgentJump
    private var window: PanelWindow?
    /// The size M last resized the panel to. Placement starts from it rather than the current frame,
    /// so a panel shrunk to fit a small display grows back on a larger one.
    private var chosenSize = PanelWindow.defaultSize
    private var observations: [Task<Void, Never>] = []

    public init(store: HUDStore, anchor: HAnchor, transcripts: any TranscriptSource, desktops: [DesktopAgentSource]) {
        self.store = store
        self.anchor = anchor
        self.transcripts = transcripts
        jump = AgentJump(store: store, desktops: desktops)
    }

    public func start() {
        guard window == nil else { return }
        let window = PanelWindow(store: store, transcripts: transcripts, jump: jump)
        self.window = window

        observations = [
            Task { [store, weak self] in
                for await isOpen in Observations({ store.isPanelOpen }) {
                    self?.setOpen(isOpen)
                }
            },
            Task { [anchor, weak self] in
                for await _ in Observations({ anchor.placement }) {
                    self?.placeIfOpen()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSWindow.didEndLiveResizeNotification,
                                                                        object: window) {
                    self?.chosenSize = window.frame.size
                }
            },
            Task { [weak self] in
                for await _ in NSWorkspace.shared.notificationCenter.notifications(
                    named: NSWorkspace.activeSpaceDidChangeNotification
                ) {
                    self?.bringToFrontIfOpen()
                }
            },
        ]
    }

    private func setOpen(_ isOpen: Bool) {
        guard let window else { return }
        if isOpen {
            place(window)
            window.orderFrontRegardless()
            window.makeKey()
        } else {
            window.orderOut(nil)
        }
    }

    private func placeIfOpen() {
        guard let window, window.isVisible else { return }
        place(window)
    }

    private func bringToFrontIfOpen() {
        guard let window, window.isVisible else { return }
        window.orderFrontRegardless()
    }

    private func place(_ window: PanelWindow) {
        window.setFrame(PanelFrame.beside(anchor.placement, size: chosenSize), display: true)
    }
}

extension PanelController {
    /// A panel that takes typing for the prompt box without activating the app's other windows, and
    /// floats on every Space like H. It is titled, with the title bar transparent and its buttons
    /// hidden, rather than borderless, because a titled window gets the system's rounded corners,
    /// shadow and edge resizing.
    fileprivate final class PanelWindow: NSPanel {
        static let defaultSize = NSSize(width: 1000, height: 740)

        init(store: HUDStore, transcripts: any TranscriptSource, jump: AgentJump) {
            super.init(
                contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
            hidesOnDeactivate = false
            becomesKeyOnlyIfNeeded = false
            isReleasedWhenClosed = false
            isMovable = false
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(button)?.isHidden = true
            }
            setFrame(NSRect(origin: .zero, size: Self.defaultSize), display: false)
            minSize = NSSize(width: 640, height: 430)

            let hosting = NSHostingView(rootView: PanelView(
                store: store,
                transcripts: transcripts,
                jump: jump,
                rosterWidthPreference: RosterWidth(defaults: .standard)
            ))
            hosting.sizingOptions = []
            contentView = hosting
        }

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        /// Double-clicking the transparent title bar would zoom the panel away from its place beside H.
        override func zoom(_ sender: Any?) {}
    }
}
