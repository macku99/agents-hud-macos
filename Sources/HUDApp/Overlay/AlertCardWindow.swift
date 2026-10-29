import AppKit
import SwiftUI

extension OverlayController {
    /// One alert as a glass card floating beside H.
    @MainActor
    final class AlertCardWindow {
        let panel: FloatingPanel
        private let host: Host
        private let hosting: FirstClickHostingView<Card>
        private let actions: Card.Actions
        private let onHover: (Bool) -> Void

        var content: AlertCardContent {
            didSet { render() }
        }

        private var isHovered = false {
            didSet { render() }
        }

        init(content: AlertCardContent, onOpen: @escaping @MainActor () -> Void,
             onDismiss: @escaping @MainActor () -> Void, onHover: @escaping (Bool) -> Void) {
            self.content = content
            actions = Card.Actions(open: onOpen, dismiss: onDismiss)
            self.onHover = onHover
            panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: AlertStack.cardWidth, height: 72))
            panel.hasShadow = true
            hosting = FirstClickHostingView(rootView: Card(content: content, isHovered: false, actions: actions))
            hosting.sizingOptions = [.intrinsicContentSize]
            host = Host(hosting: hosting)
            panel.contentView = host
            host.onHover = { [weak self] hovering in
                self?.isHovered = hovering
                onHover(hovering)
            }
        }

        /// The card's height at the stack's width, for its current content.
        var fittingHeight: CGFloat {
            ceil(hosting.fittingSize.height)
        }

        func place(_ frame: CGRect) {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            panel.orderFrontRegardless()
        }

        /// A window ordered out gets no mouse-exited, so a hover in progress ends here.
        func close() {
            panel.orderOut(nil)
            if isHovered {
                isHovered = false
                onHover(false)
            }
        }

        private func render() {
            hosting.rootView = Card(content: content, isHovered: isHovered, actions: actions)
        }
    }
}

extension OverlayController.AlertCardWindow {
    /// The glass ground under the card, tracking hover even while another app is active.
    private final class Host: NSView {
        var onHover: (Bool) -> Void = { _ in }

        init(hosting: NSView) {
            super.init(frame: .zero)
            let glass = NSVisualEffectView()
            glass.material = .popover
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 8
            glass.layer?.masksToBounds = true
            for view in [glass, hosting] {
                view.autoresizingMask = [.width, .height]
                view.frame = bounds
                addSubview(view)
            }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
    }

    /// Takes the click that reaches a window of an inactive app, so one click opens or dismisses.
    private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private struct Card: View {
        struct Actions {
            let open: @MainActor () -> Void
            let dismiss: @MainActor () -> Void
        }

        typealias Style = OverlayController.Style

        let content: OverlayController.AlertCardContent
        let isHovered: Bool
        let actions: Actions

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    marker
                    Text(verbatim: content.title)
                        .font(Font(Style.sans(size: 15, weight: .medium)))
                        .foregroundStyle(Color(nsColor: Style.fg))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(action: actions.dismiss) {
                        Text(verbatim: "×")
                            .font(Font(Style.mono(size: 15, weight: .regular)))
                            .foregroundStyle(Color(nsColor: Style.mute))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(verbatim: content.meta)
                    .font(Font(Style.mono(size: 11, weight: .regular)))
                    .foregroundStyle(Color(nsColor: Style.faint))
                if let preview = content.preview {
                    Text(verbatim: preview)
                        .font(Font(Style.sans(size: 13, weight: .regular)))
                        .foregroundStyle(Color(nsColor: Style.mute))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: OverlayController.AlertStack.cardWidth, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: actions.open)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: isHovered ? Style.accent : Style.line), lineWidth: 1)
            }
        }

        @ViewBuilder private var marker: some View {
            switch content.kind {
            case .finished:
                Circle().fill(Color(nsColor: Style.accent)).frame(width: 8, height: 8)
            case .needsInput:
                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: Style.high)).frame(width: 8, height: 8)
            }
        }
    }
}
