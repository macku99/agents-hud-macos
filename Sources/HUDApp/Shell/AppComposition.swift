import AppKit
import DesktopSessions
import Foundation
import HerdrKit
import HUDCore
import Transcript

/// Builds every part of the app once and wires them together. Parts never construct each other.
@MainActor
public final class AppComposition: NSObject, NSApplicationDelegate {
    private var store: HUDStore?
    private var overlay: OverlayController?
    private var panel: PanelController?
    private var shell: ShellController?

    override public init() {}

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ShellConfig.load(home: FileManager.default.homeDirectoryForCurrentUser)
        let desktops = config.desktops.map { DesktopAgentSource(instance: $0) }
        let store = HUDStore(sources: [HerdrAgentSource(client: LiveHerdrClient())] + desktops)
        let anchor = HAnchor()
        let transcripts = ClaudeTranscripts(configDirectories: config.transcriptDirectories)

        let overlay = OverlayController(store: store, anchor: anchor)
        let panel = PanelController(store: store, anchor: anchor, transcripts: transcripts, desktops: desktops)
        let shell = ShellController(store: store)
        overlay.start()
        panel.start()
        shell.start()
        Task { await store.start() }

        self.store = store
        self.overlay = overlay
        self.panel = panel
        self.shell = shell
    }
}
