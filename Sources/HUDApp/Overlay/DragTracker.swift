import CoreGraphics

extension OverlayController {
    /// Tells a click on H from a drag: the press becomes a drag once the pointer travels more than
    /// 4 pt, and stays one until release.
    struct DragTracker {
        enum Release { case click, drag }

        static let threshold: CGFloat = 4

        let start: CGPoint
        private(set) var isDragging = false

        init(start: CGPoint) {
            self.start = start
        }

        /// The pointer's translation since the press while dragging; `nil` while it is still a click.
        mutating func move(to point: CGPoint) -> CGVector? {
            let translation = CGVector(dx: point.x - start.x, dy: point.y - start.y)
            if !isDragging, (translation.dx * translation.dx + translation.dy * translation.dy).squareRoot() > Self.threshold {
                isDragging = true
            }
            return isDragging ? translation : nil
        }

        func release() -> Release {
            isDragging ? .drag : .click
        }
    }
}
