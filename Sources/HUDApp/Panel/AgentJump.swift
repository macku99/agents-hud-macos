import AppKit
import DesktopSessions
import HUDCore

extension PanelController {
    /// Where going to an agent takes M: a herdr agent's pane in the terminal, or the Desktop
    /// instance running a session.
    enum Destination: Equatable {
        case terminal
        case desktop

        init(of agent: AgentSnapshot) {
            self = agent.herdr != nil ? .terminal : .desktop
        }
    }

    /// Brings M to where an agent runs.
    @MainActor
    struct AgentJump {
        let store: HUDStore
        let desktops: [DesktopAgentSource]

        func go(to agent: AgentSnapshot) {
            switch Destination(of: agent) {
            case .terminal:
                Task {
                    await store.focus(agent.key)
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first?.activate()
                }
            case .desktop:
                // Both instances are the same app, so the instance is found by the session's process,
                // not by bundle id. Opening the session itself needs a deep link aimed at that process.
                let pid = desktops.lazy.compactMap { $0.applicationPID(for: agent.key) }.first
                pid.flatMap { NSRunningApplication(processIdentifier: $0) }?.activate()
            }
        }
    }
}
