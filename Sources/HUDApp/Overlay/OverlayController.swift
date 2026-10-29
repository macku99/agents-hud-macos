import AppKit
import HUDCore
import Observation

/// Owns H and the alerts that float above every Space.
@MainActor
public final class OverlayController {
    private let store: HUDStore
    private let anchor: HAnchor
    private let memory = HPositionMemory(defaults: .standard)
    private var hWindow: FloatingPanel?
    private var tile: HTileView?
    /// H's tile frame and the display it is on; the window is larger by the tile's padding.
    private var position: (frame: CGRect, display: Display)?
    private var dragStart: CGRect?
    private var isHUDVisible = false
    private var cards: [AlertCardContent] = []
    private var cardWindows: [UUID: AlertCardWindow] = [:]
    /// The cards on screen and where, as last laid out.
    private var placedCards: [AlertStack.Placement] = []
    private var timers: AlertTimers?
    private var observers: [NSObjectProtocol] = []
    private var storeObservation: Task<Void, Never>?

    public init(store: HUDStore, anchor: HAnchor) {
        self.store = store
        self.anchor = anchor
    }

    public func start() {
        guard hWindow == nil else { return }
        let tile = HTileView()
        let window = FloatingPanel(contentRect: tile.frame)
        window.contentView = tile
        tile.onClick = { [weak self] in self?.store.togglePanel() }
        tile.onDrag = { [weak self] translation in self?.drag(by: translation) }
        tile.onDragEnd = { [weak self] in self?.endDrag() }
        self.tile = tile
        hWindow = window
        timers = AlertTimers(scheduler: AlertTimers.TaskScheduler()) { [weak self] id in self?.store.dismissAlert(id) }

        restorePosition()
        observeSystem()
        observeStore()
    }

    // MARK: - Position

    private static func displays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            HPositionMemory.displayID(from: screen.deviceDescription).map {
                Display(id: $0, frame: screen.frame, visibleFrame: screen.visibleFrame)
            }
        }
    }

    private func restorePosition() {
        guard let restored = HPosition.restore(displays: Self.displays(), lastDisplay: memory.lastDisplay,
                                               savedOffset: memory.offset(on:)) else { return }
        place(restored.frame, on: restored.display)
    }

    private func drag(by translation: CGVector) {
        guard let start = dragStart ?? position?.frame else { return }
        dragStart = start
        let moved = start.offsetBy(dx: translation.dx, dy: translation.dy)
        guard let display = HPosition.display(for: moved, among: Self.displays()) else { return }
        place(HPosition.clamped(moved, in: display.visibleFrame), on: display)
    }

    private func endDrag() {
        dragStart = nil
        guard let position else { return }
        memory.save(offset: HPosition.offset(of: position.frame, on: position.display), on: position.display.id)
    }

    private func place(_ frame: CGRect, on display: Display) {
        position = (frame, display)
        let padding = HTileView.padding
        hWindow?.setFrame(frame.insetBy(dx: -padding, dy: -padding), display: true)
        anchor.placement = HPosition.placement(frame: frame, on: display)
        layoutCards()
    }

    // MARK: - Store

    private struct StoreState: Sendable {
        var isHUDVisible: Bool
        var isAnyAgentWorking: Bool
        var badgeCount: Int
        var alerts: [HUDAlert]
        var roster: [RosterEntry]
    }

    private func observeStore() {
        let store = store
        let states = Observations {
            StoreState(isHUDVisible: store.isHUDVisible, isAnyAgentWorking: store.isAnyAgentWorking,
                       badgeCount: store.badgeCount, alerts: store.alerts, roster: store.roster)
        }
        storeObservation = Task { [weak self] in
            for await state in states {
                self?.apply(state)
            }
        }
    }

    private func apply(_ state: StoreState) {
        if state.isHUDVisible != isHUDVisible {
            isHUDVisible = state.isHUDVisible
            if isHUDVisible { hWindow?.orderFrontRegardless() } else { hWindow?.orderOut(nil) }
        }
        tile?.isWorking = state.isAnyAgentWorking
        tile?.badge = OverlayText.badge(count: state.badgeCount)
        updateCards(AlertCardContent.cards(for: state.alerts, roster: state.roster))
    }

    // MARK: - Alerts

    private func updateCards(_ contents: [AlertCardContent]) {
        let ids = Set(contents.map(\.id))
        for (id, window) in cardWindows where !ids.contains(id) {
            window.close()
            cardWindows[id] = nil
        }
        for content in contents {
            if let window = cardWindows[content.id] {
                if window.content != content { window.content = content }
            } else {
                cardWindows[content.id] = makeCardWindow(content)
            }
        }
        cards = contents
        layoutCards()
    }

    private func makeCardWindow(_ content: AlertCardContent) -> AlertCardWindow {
        let id = content.id
        let key = content.key
        return AlertCardWindow(
            content: content,
            onOpen: { [weak self] in self?.store.openPanel(on: key) },
            onDismiss: { [weak self] in self?.store.dismissAlert(id) },
            onHover: { [weak self] hovering in
                if hovering { self?.timers?.hoverBegan(id) } else { self?.timers?.hoverEnded(id) }
            }
        )
    }

    /// Places the cards the stack fits and closes the rest. Only placed cards run their auto-dismiss
    /// timer, so nothing is dismissed unseen; an unchanged layout leaves every window where it is.
    private func layoutCards() {
        guard let position else { return }
        let stack = cards.compactMap { content in
            cardWindows[content.id].map { AlertStack.Card(id: content.id, height: $0.fittingHeight) }
        }
        let placements = AlertStack.placements(of: stack, around: HPosition.placement(frame: position.frame,
                                                                                     on: position.display),
                                               isHUDVisible: isHUDVisible)
        guard placements != placedCards else { return }
        let placedIDs = Set(placements.map(\.id))
        for (id, window) in cardWindows where !placedIDs.contains(id) { window.close() }
        for placement in placements { cardWindows[placement.id]?.place(placement.frame) }
        placedCards = placements
        timers?.show(placements.map(\.id))
    }

    // MARK: - System

    private func observeSystem() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringToFront() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restorePosition() }
        })
    }

    private func bringToFront() {
        guard isHUDVisible else { return }
        hWindow?.orderFrontRegardless()
        for placement in placedCards { cardWindows[placement.id]?.panel.orderFrontRegardless() }
    }
}
