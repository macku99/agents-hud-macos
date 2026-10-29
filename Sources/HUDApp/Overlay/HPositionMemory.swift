import AppKit
import Foundation

extension OverlayController {
    /// H's saved position on each display and the display it was last on.
    struct HPositionMemory {
        private static let offsetKeyPrefix = "overlay.h.offset."
        private static let lastDisplayKey = "overlay.h.lastDisplay"

        private let defaults: UserDefaults

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        static func displayID(from deviceDescription: [NSDeviceDescriptionKey: Any]) -> UInt32? {
            (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }

        var lastDisplay: UInt32? {
            (defaults.object(forKey: Self.lastDisplayKey) as? NSNumber)?.uint32Value
        }

        func offset(on display: UInt32) -> CGPoint? {
            guard let pair = defaults.array(forKey: Self.offsetKeyPrefix + String(display)) as? [Double],
                  pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }

        func save(offset: CGPoint, on display: UInt32) {
            defaults.set([Double(offset.x), Double(offset.y)], forKey: Self.offsetKeyPrefix + String(display))
            defaults.set(NSNumber(value: display), forKey: Self.lastDisplayKey)
        }
    }
}
