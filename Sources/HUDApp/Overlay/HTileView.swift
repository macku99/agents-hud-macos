import AppKit

extension OverlayController {
    /// H: the app icon's tile (the glass tile with its glyph when there is no icon art), the working ring and
    /// the attention badge. Reports clicks and drags; where H goes is the controller's call.
    final class HTileView: NSView {
        /// Room around the tile for the ring, the badge and the shadow.
        nonisolated static let padding: CGFloat = 16
        nonisolated static let ringOutset: CGFloat = 6
        nonisolated static let ringLineWidth: CGFloat = 1.5
        /// How far the badge pill sits past the tile's right edge and above its top.
        nonisolated static let badgeOffset = CGSize(width: 10, height: 8)
        nonisolated static let badgeCutout: CGFloat = 2
        nonisolated static var badgeOverhang: CGSize {
            CGSize(width: badgeOffset.width + badgeCutout, height: badgeOffset.height + badgeCutout)
        }

        var onClick: () -> Void = {}
        /// The pointer's translation since the press, once the press has become a drag.
        var onDrag: (CGVector) -> Void = { _ in }
        var onDragEnd: () -> Void = {}

        var isWorking = false {
            didSet { if isWorking != oldValue { ring.isPulsing = isWorking } }
        }

        var badge: String? {
            didSet { if badge != oldValue { layoutBadge() } }
        }

        private var tileRect: CGRect { bounds.insetBy(dx: Self.padding, dy: Self.padding) }
        private let glass = NSVisualEffectView()
        private let face = Face()
        private let ring = Ring()
        private let badgeView = Badge()
        private var drag: DragTracker?

        init() {
            let side = HPosition.tileSize.width + 2 * Self.padding
            super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
            wantsLayer = true
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.18
            layer?.shadowRadius = 6
            layer?.shadowOffset = CGSize(width: 0, height: -2)
            layer?.shadowPath = CGPath(roundedRect: tileRect, cornerWidth: 18, cornerHeight: 18, transform: nil)

            glass.material = .popover
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 18
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.frame = tileRect
            face.frame = tileRect
            ring.frame = tileRect.insetBy(dx: -Ring.inset - Self.ringOutset, dy: -Ring.inset - Self.ringOutset)
            ring.isHidden = true
            badgeView.isHidden = true
            let surface: [NSView] = if let art = Self.iconArt { [Self.artView(art, frame: tileRect)] } else { [glass, face] }
            for view in surface + [ring, badgeView] { addSubview(view) }
        }

        /// The app icon's art, which bundle-app.sh ships as HTile.png. A development build run from `.build` has
        /// no bundle and keeps the drawn glass tile.
        private static let iconArt = Bundle.main.url(forResource: "HTile", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))

        private static func artView(_ art: NSImage, frame: CGRect) -> NSView {
            let view = NSImageView(frame: frame)
            view.image = art
            view.imageScaling = .scaleAxesIndependently
            view.wantsLayer = true
            view.layer?.cornerRadius = 18
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
            return view
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let badgeFrame = badgeView.isHidden ? nil : badgeView.frame
            return Self.takesMouse(at: convert(point, from: superview), tileRect: tileRect, badgeFrame: badgeFrame)
                ? self : nil
        }

        /// The tile and a shown badge act as H: a click there toggles the panel and a drag moves H. A press
        /// on the rest of the padding reaches no view and does nothing.
        nonisolated static func takesMouse(at point: CGPoint, tileRect: CGRect, badgeFrame: CGRect?) -> Bool {
            tileRect.contains(point) || badgeFrame?.contains(point) == true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            drag = DragTracker(start: NSEvent.mouseLocation)
        }

        override func mouseDragged(with event: NSEvent) {
            if let translation = drag?.move(to: NSEvent.mouseLocation) { onDrag(translation) }
        }

        override func mouseUp(with event: NSEvent) {
            guard let drag else { return }
            self.drag = nil
            switch drag.release() {
            case .click: onClick()
            case .drag: onDragEnd()
            }
        }

        private func layoutBadge() {
            badgeView.text = badge
            badgeView.isHidden = badge == nil
            guard badge != nil else { return }
            let pill = Self.badgePillFrame(tileRect: tileRect, textWidth: badgeView.textWidth)
            badgeView.frame = pill.insetBy(dx: -Self.badgeCutout, dy: -Self.badgeCutout)
        }

        /// The count pill: at least 20 pt wide, `badgeOffset` past the tile's right edge and above its top.
        nonisolated static func badgePillFrame(tileRect: CGRect, textWidth: CGFloat) -> CGRect {
            let width = max(20, ceil(textWidth) + 12)
            return CGRect(x: tileRect.maxX + badgeOffset.width - width, y: tileRect.maxY + badgeOffset.height - 20,
                          width: width, height: 20)
        }
    }
}

extension OverlayController.HTileView {
    /// The hairline, inner rim and H glyph drawn over the glass.
    private final class Face: NSView {
        override func draw(_ dirtyRect: NSRect) {
            typealias Style = OverlayController.Style
            let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 17.5, yRadius: 17.5)
            outer.lineWidth = 1
            Style.line.setStroke()
            outer.stroke()

            let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 3.5, dy: 3.5), xRadius: 13.5, yRadius: 13.5)
            rim.lineWidth = 1
            Style.fg.withAlphaComponent(0.14).setStroke()
            rim.stroke()

            // The glyph sits in a 22 pt box drawn on a 24-unit grid: stems at 6 and 18, crossbar at 12.
            let unit: CGFloat = 22 / 24
            let box = CGRect(x: bounds.midX - 11, y: bounds.midY - 11, width: 22, height: 22)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * unit, y: box.minY + y * unit) }
            func line(_ from: CGPoint, _ to: CGPoint, _ color: NSColor) {
                let path = NSBezierPath()
                path.move(to: from)
                path.line(to: to)
                path.lineWidth = 2.6 * unit
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            line(point(6, 12), point(18, 12), Style.accent)
            line(point(6, 4.5), point(6, 19.5), Style.fg)
            line(point(18, 4.5), point(18, 19.5), Style.fg)
        }
    }

    /// The green ring 6 pt outside the tile that pulses while any agent works.
    private final class Ring: NSView {
        /// Room inside the view's edge so the stroke is not clipped.
        static let inset: CGFloat = 2

        var isPulsing = false {
            didSet {
                isHidden = !isPulsing
                if isPulsing { Pulse.start(on: layer, every: .seconds(1.2)) } else { Pulse.stop(on: layer) }
            }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: Self.inset, dy: Self.inset), xRadius: 23, yRadius: 23)
            path.lineWidth = OverlayController.HTileView.ringLineWidth
            OverlayController.Style.ring.setStroke()
            path.stroke()
        }

    }

    /// The design system's one animation: opacity 1 to 0.35 and back, each way taking `every`, for as
    /// long as it runs.
    private enum Pulse {
        static func start(on layer: CALayer?, every halfCycle: Duration) {
            guard let layer, layer.animation(forKey: "pulse") == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.35
            pulse.duration = Double(halfCycle.components.seconds) + Double(halfCycle.components.attoseconds) / 1e18
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "pulse")
        }

        static func stop(on layer: CALayer?) {
            layer?.removeAnimation(forKey: "pulse")
        }
    }

    /// The light green count pill in a British racing green ring, pulsing while it shows.
    private final class Badge: NSView {
        var text: String? { didSet { needsDisplay = true } }

        override var isHidden: Bool {
            didSet { if isHidden { Pulse.stop(on: layer) } else { Pulse.start(on: layer, every: .seconds(2.4)) } }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        private var attributedText: NSAttributedString {
            NSAttributedString(string: text ?? "", attributes: [
                .font: OverlayController.Style.mono(size: 11, weight: .semibold),
                .foregroundColor: OverlayController.Style.badgeBorder,
            ])
        }

        var textWidth: CGFloat { attributedText.size().width }

        override func draw(_ dirtyRect: NSRect) {
            let ring = bounds
            OverlayController.Style.badgeBorder.setFill()
            NSBezierPath(roundedRect: ring, xRadius: ring.height / 2, yRadius: ring.height / 2).fill()
            let cutout = OverlayController.HTileView.badgeCutout
            let pill = bounds.insetBy(dx: cutout, dy: cutout)
            OverlayController.Style.badgeFill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            let text = attributedText
            let size = text.size()
            text.draw(at: CGPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
        }
    }
}
