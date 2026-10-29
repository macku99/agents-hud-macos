import CoreGraphics
import Foundation

extension OverlayController {
    /// Where the alert cards go around H.
    enum AlertStack {
        struct Card: Hashable {
            let id: UUID
            let height: CGFloat
        }

        struct Placement: Hashable {
            let id: UUID
            let frame: CGRect
        }

        static let cardWidth: CGFloat = 340
        static let gap: CGFloat = 8
        static let margin: CGFloat = 4

        /// The cards that go on screen, nearest H first: none while the HUD is hidden, and only those the
        /// stack fits. Anything left out is not on screen, so its auto-dismiss timer must not run.
        static func placements(of cards: [Card], around h: HAnchor.Placement, isHUDVisible: Bool) -> [Placement] {
            guard isHUDVisible else { return [] }
            // Stack from everything H draws above and below the tile (badge, ring), not from the tile.
            let reach = HPosition.overhang
            let drawn = CGRect(x: h.frame.minX, y: h.frame.minY - reach.bottom, width: h.frame.width,
                               height: h.frame.height + reach.top + reach.bottom)
            let frames = frames(heights: cards.map(\.height), around: drawn, in: h.displayVisibleFrame)
            return zip(cards, frames).map { Placement(id: $0.id, frame: $1) }
        }

        /// Frames for cards of the given heights, nearest H first. The stack goes above H when it all
        /// fits there, else below; when neither side holds it all, the roomier side shows the cards
        /// nearest H that fit, so the result can be shorter than `heights`.
        static func frames(heights: [CGFloat], around hFrame: CGRect, in visibleFrame: CGRect) -> [CGRect] {
            let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
            let roomAbove = bounds.maxY - (hFrame.maxY + gap)
            let roomBelow = (hFrame.minY - gap) - bounds.minY
            let needed = heights.reduce(0, +) + gap * CGFloat(max(heights.count - 1, 0))
            let above = needed <= roomAbove || (needed > roomBelow && roomAbove >= roomBelow)
            let room = above ? roomAbove : roomBelow
            let x = max(min(hFrame.minX, bounds.maxX - cardWidth), bounds.minX)

            var frames: [CGRect] = []
            var used: CGFloat = 0
            for height in heights {
                let start = used + (frames.isEmpty ? 0 : gap)
                guard start + height <= room else { break }
                let y = above ? hFrame.maxY + gap + start : hFrame.minY - gap - start - height
                frames.append(CGRect(x: x, y: y, width: cardWidth, height: height))
                used = start + height
            }
            return frames
        }
    }
}
