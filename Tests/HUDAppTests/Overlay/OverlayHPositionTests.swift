import CoreGraphics
import Testing
@testable import HUDApp

@Suite struct OverlayHPositionTests {
    typealias Position = OverlayController.HPosition
    typealias Display = OverlayController.Display

    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let main = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 830),
                       visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    let side = Display(id: 2, frame: CGRect(x: 1000, y: 100, width: 800, height: 600),
                       visibleFrame: CGRect(x: 1000, y: 100, width: 800, height: 600))

    @Test func clampLeavesAFrameInsideTheMarginAlone() {
        let frame = CGRect(x: 100, y: 100, width: 56, height: 56)
        #expect(Position.clamped(frame, in: visible) == frame)
    }

    @Test func overhangIsHowFarTheRingAndBadgeReachPastTheTile() {
        // The ring is 6 pt out with a 1.5 pt stroke; the badge pill is 10 pt right and 8 pt up, plus its 2 pt cutout.
        #expect(Position.overhang == Position.Overhang(top: 10, left: 6.75, bottom: 6.75, right: 12))
    }

    @Test func clampKeepsEverythingHDrawsFourPointsFromEveryEdge() {
        #expect(Position.clamped(CGRect(x: -30, y: -30, width: 56, height: 56), in: visible)
            == CGRect(x: 10.75, y: 10.75, width: 56, height: 56))
        #expect(Position.clamped(CGRect(x: 990, y: 790, width: 56, height: 56), in: visible)
            == CGRect(x: 928, y: 730, width: 56, height: 56))
    }

    @Test func clampWorksOnADisplayAwayFromTheOrigin() {
        let frame = CGRect(x: 900, y: 50, width: 56, height: 56)
        #expect(Position.clamped(frame, in: side.visibleFrame) == CGRect(x: 1010.75, y: 110.75, width: 56, height: 56))
    }

    @Test func defaultFrameSitsInTheTopLeftOfTheVisibleFrame() {
        let frame = Position.defaultFrame(in: visible)
        #expect(frame.size == Position.tileSize)
        #expect(frame.minX == visible.minX + Position.defaultInset)
        #expect(frame.maxY == visible.maxY - Position.defaultInset)
    }

    @Test func displayIsTheOneHoldingTheFramesCentre() {
        let onSide = CGRect(x: 1100, y: 300, width: 56, height: 56)
        #expect(Position.display(for: onSide, among: [main, side]) == side)
        let straddling = CGRect(x: 960, y: 300, width: 56, height: 56)
        #expect(Position.display(for: straddling, among: [main, side]) == main)
    }

    @Test func displayIsTheNearestWhenTheCentreIsOnNone() {
        let pastSidesRightEdge = CGRect(x: 1790, y: 300, width: 56, height: 56)
        #expect(Position.display(for: pastSidesRightEdge, among: [main, side]) == side)
        let pastMainsLeftEdge = CGRect(x: -100, y: 300, width: 56, height: 56)
        #expect(Position.display(for: pastMainsLeftEdge, among: [main, side]) == main)
        #expect(Position.display(for: pastMainsLeftEdge, among: []) == nil)
    }

    @Test func restoreUsesTheLastDisplayAndItsSavedOffset() {
        let restored = Position.restore(displays: [main, side], lastDisplay: 2, savedOffset: { id in
            id == 2 ? CGPoint(x: 200, y: 150) : nil
        })
        #expect(restored?.display == side)
        #expect(restored?.frame == CGRect(x: 1200, y: 250, width: 56, height: 56))
    }

    @Test func restoreFallsBackToTheMainDisplayWhenTheLastIsGone() {
        let restored = Position.restore(displays: [main], lastDisplay: 2, savedOffset: { id in
            id == 1 ? CGPoint(x: 300, y: 400) : CGPoint(x: 10, y: 10)
        })
        #expect(restored?.display == main)
        #expect(restored?.frame == CGRect(x: 300, y: 400, width: 56, height: 56))
    }

    @Test func restoreUsesTheDefaultWithoutASavedOffset() {
        let restored = Position.restore(displays: [main, side], lastDisplay: nil, savedOffset: { _ in nil })
        #expect(restored?.display == main)
        #expect(restored?.frame == Position.defaultFrame(in: main.visibleFrame))
    }

    @Test func restoreClampsAnOffsetThatNoLongerFits() {
        let restored = Position.restore(displays: [side], lastDisplay: 2, savedOffset: { _ in CGPoint(x: 5000, y: -40) })
        #expect(restored?.frame == CGRect(x: 1728, y: 110.75, width: 56, height: 56))
    }

    @Test func restoreWithoutDisplaysHasNothingToPlace() {
        #expect(Position.restore(displays: [], lastDisplay: 1, savedOffset: { _ in nil }) == nil)
    }

    @Test func offsetIsRelativeToTheDisplayFrame() {
        let frame = CGRect(x: 1200, y: 250, width: 56, height: 56)
        #expect(Position.offset(of: frame, on: side) == CGPoint(x: 200, y: 150))
    }

    @Test func placementPairsTheTileWithItsDisplaysVisibleFrame() {
        let frame = CGRect(x: 1200, y: 250, width: 56, height: 56)
        #expect(Position.placement(frame: frame, on: side)
            == HAnchor.Placement(frame: frame, displayVisibleFrame: side.visibleFrame))
    }
}
