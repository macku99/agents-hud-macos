import CoreGraphics
import Foundation

extension PanelController {
    /// The roster column's width, as M last dragged it.
    struct RosterWidth {
        static let range: ClosedRange<CGFloat> = 220...480
        static let standard: CGFloat = 300
        static let key = "panel.rosterWidth"

        let defaults: UserDefaults

        static func clamped(_ width: CGFloat) -> CGFloat {
            min(max(width, range.lowerBound), range.upperBound)
        }

        var stored: CGFloat {
            guard let width = defaults.object(forKey: Self.key) as? Double else { return Self.standard }
            return Self.clamped(width)
        }

        func store(_ width: CGFloat) {
            defaults.set(Double(Self.clamped(width)), forKey: Self.key)
        }
    }
}
