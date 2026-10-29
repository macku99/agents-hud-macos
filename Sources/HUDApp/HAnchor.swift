import CoreGraphics
import Observation

/// Where H currently is. The overlay writes it; the panel and alerts read it to place themselves.
@MainActor
@Observable
public final class HAnchor {
    public struct Placement: Hashable, Sendable {
        /// H's frame in screen coordinates.
        public var frame: CGRect
        /// The visible frame (menu bar and Dock excluded) of the display H is on.
        public var displayVisibleFrame: CGRect

        public init(frame: CGRect, displayVisibleFrame: CGRect) {
            self.frame = frame
            self.displayVisibleFrame = displayVisibleFrame
        }
    }

    /// Both frames change together, so a reader never pairs H with another display's bounds.
    public var placement = Placement(frame: .zero, displayVisibleFrame: .zero)

    public init() {}
}
