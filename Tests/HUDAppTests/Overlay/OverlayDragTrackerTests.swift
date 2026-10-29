import CoreGraphics
import Testing
@testable import HUDApp

@Suite struct OverlayDragTrackerTests {
    typealias Tracker = OverlayController.DragTracker

    @Test func aPressAndReleaseWithoutMovementIsAClick() {
        let tracker = Tracker(start: CGPoint(x: 100, y: 100))
        #expect(tracker.release() == .click)
    }

    @Test func movementWithinFourPointsStaysAClick() {
        var tracker = Tracker(start: CGPoint(x: 100, y: 100))
        #expect(tracker.move(to: CGPoint(x: 103, y: 101)) == nil)
        #expect(tracker.move(to: CGPoint(x: 104, y: 100)) == nil)
        #expect(tracker.release() == .click)
    }

    @Test func movementPastFourPointsStartsADrag() {
        var tracker = Tracker(start: CGPoint(x: 100, y: 100))
        #expect(tracker.move(to: CGPoint(x: 103, y: 103)) == CGVector(dx: 3, dy: 3))
        #expect(tracker.release() == .drag)
    }

    @Test func aDragKeepsGoingWhenThePointerComesBack() {
        var tracker = Tracker(start: CGPoint(x: 100, y: 100))
        _ = tracker.move(to: CGPoint(x: 110, y: 100))
        #expect(tracker.move(to: CGPoint(x: 101, y: 100)) == CGVector(dx: 1, dy: 0))
        #expect(tracker.release() == .drag)
    }
}
