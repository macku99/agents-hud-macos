import CoreGraphics

extension PanelController {
    /// Where the panel goes beside H: right of it, or left when the right side lacks room, top edges
    /// level, kept inside the display's visible frame.
    enum PanelFrame {
        static let gap: CGFloat = 12
        static let margin: CGFloat = 12

        static func beside(_ placement: HAnchor.Placement, size: CGSize) -> CGRect {
            let h = placement.frame
            let bounds = placement.displayVisibleFrame.insetBy(dx: margin, dy: margin)
            guard !bounds.isEmpty else {
                return CGRect(x: h.maxX + gap, y: h.maxY - size.height, width: size.width, height: size.height)
            }

            let width = min(size.width, bounds.width)
            let height = min(size.height, bounds.height)
            let rightX = h.maxX + gap
            let x = rightX + width <= bounds.maxX ? rightX : h.minX - gap - width
            return CGRect(
                x: min(max(x, bounds.minX), bounds.maxX - width),
                y: min(max(h.maxY - height, bounds.minY), bounds.maxY - height),
                width: width,
                height: height
            )
        }
    }
}
