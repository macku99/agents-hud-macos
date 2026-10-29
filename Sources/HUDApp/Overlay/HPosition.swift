import CoreGraphics

extension OverlayController {
    /// A connected display as the overlay places H on it, in screen coordinates.
    struct Display: Hashable {
        /// `NSScreenNumber` of the display.
        var id: UInt32
        var frame: CGRect
        var visibleFrame: CGRect
    }

    /// Where H's tile goes. Frames are the 56 pt tile, not its window, which is larger to fit the ring
    /// and badge.
    enum HPosition {
        /// How far H's drawing reaches past the tile on each side.
        struct Overhang: Hashable {
            var top: CGFloat
            var left: CGFloat
            var bottom: CGFloat
            var right: CGFloat
        }

        static let tileSize = CGSize(width: 56, height: 56)
        static let margin: CGFloat = 4
        static let defaultInset: CGFloat = 24

        /// The working ring on every side, and the badge where it sticks out further, at top-right. Both
        /// count whether or not they show, so H does not move when they appear.
        static let overhang: Overhang = {
            let ring = HTileView.ringOutset + HTileView.ringLineWidth / 2
            let badge = HTileView.badgeOverhang
            return Overhang(top: max(ring, badge.height), left: ring, bottom: ring, right: max(ring, badge.width))
        }()

        /// Keeps the tile, its ring and its badge 4 pt inside the visible frame.
        static func clamped(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
            let minX = visibleFrame.minX + margin + overhang.left
            let maxX = visibleFrame.maxX - margin - overhang.right - frame.width
            let minY = visibleFrame.minY + margin + overhang.bottom
            let maxY = visibleFrame.maxY - margin - overhang.top - frame.height
            var clamped = frame
            clamped.origin.x = min(max(frame.minX, minX), maxX)
            clamped.origin.y = min(max(frame.minY, minY), maxY)
            return clamped
        }

        static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
            CGRect(x: visibleFrame.minX + defaultInset, y: visibleFrame.maxY - defaultInset - tileSize.height,
                   width: tileSize.width, height: tileSize.height)
        }

        /// The display holding the frame's centre, or the nearest one when a drag pushes the centre past
        /// every display's edge.
        static func display(for frame: CGRect, among displays: [Display]) -> Display? {
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            func distance(to display: Display) -> CGFloat {
                let dx = max(display.frame.minX - centre.x, 0, centre.x - display.frame.maxX)
                let dy = max(display.frame.minY - centre.y, 0, centre.y - display.frame.maxY)
                return dx * dx + dy * dy
            }
            return displays.first { $0.frame.contains(centre) } ?? displays.min { distance(to: $0) < distance(to: $1) }
        }

        /// Puts H on the last display it was on, or the main display when that one is gone, at the offset
        /// saved for that display, or the default position without one.
        static func restore(displays: [Display], lastDisplay: UInt32?,
                            savedOffset: (UInt32) -> CGPoint?) -> (display: Display, frame: CGRect)? {
            guard let display = displays.first(where: { $0.id == lastDisplay }) ?? displays.first else { return nil }
            guard let offset = savedOffset(display.id) else {
                return (display, defaultFrame(in: display.visibleFrame))
            }
            let saved = CGRect(origin: CGPoint(x: display.frame.minX + offset.x, y: display.frame.minY + offset.y),
                               size: tileSize)
            return (display, clamped(saved, in: display.visibleFrame))
        }

        /// Saved relative to the display so a rearranged display keeps H where it was on it.
        static func offset(of frame: CGRect, on display: Display) -> CGPoint {
            CGPoint(x: frame.minX - display.frame.minX, y: frame.minY - display.frame.minY)
        }

        static func placement(frame: CGRect, on display: Display) -> HAnchor.Placement {
            HAnchor.Placement(frame: frame, displayVisibleFrame: display.visibleFrame)
        }
    }
}
