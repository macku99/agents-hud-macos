import AppKit
import Carbon

/// A system-wide shortcut, described once for both Carbon registration and the menu's key equivalent.
struct ShellHotKey: Hashable, Sendable {
    let id: UInt32
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let keyModifiers: NSEvent.ModifierFlags
    let symbol: String
    let command: ShellCommand

    static let togglePanel = ShellHotKey(
        id: 1,
        keyCode: UInt32(kVK_ANSI_H),
        carbonModifiers: UInt32(cmdKey | controlKey | optionKey),
        keyEquivalent: "h",
        keyModifiers: [.command, .control, .option],
        symbol: "⌃⌥⌘H",
        command: .togglePanel
    )

    static let toggleHUD = ShellHotKey(
        id: 2,
        keyCode: UInt32(kVK_ANSI_H),
        carbonModifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
        keyEquivalent: "h",
        keyModifiers: [.command, .control, .option, .shift],
        symbol: "⇧⌃⌥⌘H",
        command: .toggleHUD
    )

    static let all: [ShellHotKey] = [.togglePanel, .toggleHUD]

    /// `NSEvent.ModifierFlags` is not `Hashable`; the id alone identifies a shortcut.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Registers every shortcut and returns the ones the system refused.
    @MainActor
    static func registerAll(
        with registrar: any ShellHotKeyRegistering,
        perform: @escaping @MainActor (ShellCommand) -> Void
    ) -> [ShellHotKey] {
        all.filter { hotKey in
            !registrar.register(hotKey) { perform(hotKey.command) }
        }
    }
}

@MainActor
protocol ShellHotKeyRegistering {
    /// Returns false when the system refuses the shortcut. Whether a shortcut another app already
    /// holds is refused has not been verified.
    func register(_ hotKey: ShellHotKey, onPress: @escaping @MainActor () -> Void) -> Bool
}

extension ShellHotKey {
    /// Carbon hot keys need no Accessibility permission. Carbon keeps an unretained pointer to the
    /// registrar, so it must live as long as the app.
    @MainActor
    final class SystemRegistrar: ShellHotKeyRegistering {
        private static let signature: OSType = 0x4848_5544 // "HHUD"

        private var actions: [UInt32: @MainActor () -> Void] = [:]
        private var hotKeyRefs: [EventHotKeyRef] = []
        private var handlerRef: EventHandlerRef?

        func register(_ hotKey: ShellHotKey, onPress: @escaping @MainActor () -> Void) -> Bool {
            guard installPressHandler() else { return false }
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotKey.keyCode,
                hotKey.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: hotKey.id),
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            guard status == OSStatus(noErr), let hotKeyRef else { return false }
            hotKeyRefs.append(hotKeyRef)
            actions[hotKey.id] = onPress
            return true
        }

        private func installPressHandler() -> Bool {
            if handlerRef != nil { return true }
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard status == OSStatus(noErr) else { return status }
                    let registrar = Unmanaged<SystemRegistrar>.fromOpaque(userData).takeUnretainedValue()
                    // The application event target delivers on the main run loop.
                    return MainActor.assumeIsolated { registrar.press(hotKeyID) }
                },
                1,
                &pressed,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
            return status == OSStatus(noErr)
        }

        private func press(_ hotKeyID: EventHotKeyID) -> OSStatus {
            guard hotKeyID.signature == Self.signature, let action = actions[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            action()
            return OSStatus(noErr)
        }
    }
}
