import CoreGraphics
import Foundation
import Testing
@testable import HUDApp

@Suite struct OverlayAlertStackTests {
    typealias Stack = OverlayController.AlertStack

    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func h(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 56, height: 56)
    }

    @Test func noAlertsNoFrames() {
        #expect(Stack.frames(heights: [], around: h(x: 100, y: 100), in: visible).isEmpty)
    }

    @Test func stacksAboveHEightPointsApartNearestFirst() {
        let frames = Stack.frames(heights: [60, 80], around: h(x: 100, y: 100), in: visible)
        #expect(frames == [
            CGRect(x: 100, y: 164, width: 340, height: 60),
            CGRect(x: 100, y: 232, width: 340, height: 80),
        ])
    }

    @Test func stacksBelowWhenThereIsNoRoomAbove() {
        let frames = Stack.frames(heights: [60, 40], around: h(x: 100, y: 700), in: visible)
        #expect(frames == [
            CGRect(x: 100, y: 632, width: 340, height: 60),
            CGRect(x: 100, y: 584, width: 340, height: 40),
        ])
    }

    @Test func staysAboveWhenTheStackExactlyFits() {
        // 796 (top minus margin) − 164 (H top plus gap) = 632 = 300 + 8 + 324
        let frames = Stack.frames(heights: [300, 324], around: h(x: 100, y: 100), in: visible)
        #expect(frames.last?.maxY == 796)
        #expect(frames.first?.minY == 164)
    }

    @Test func movesTheWholeStackBelowWhenOnlyPartFitsAbove() {
        let frames = Stack.frames(heights: [60, 60], around: h(x: 100, y: 640), in: visible)
        #expect(frames.map(\.maxY) == [632, 564])
    }

    @Test func keepsOnlyTheNearestCardsThatFitWhenNeitherSideHoldsAll() {
        // above: 796 − 464 = 332; below: 400 − 8 − 4 = 388
        let frames = Stack.frames(heights: [200, 150, 100], around: h(x: 100, y: 400), in: visible)
        #expect(frames == [
            CGRect(x: 100, y: 192, width: 340, height: 200),
            CGRect(x: 100, y: 34, width: 340, height: 150),
        ])
    }

    @Test func shiftsLeftToStayInsideTheRightEdge() {
        let frames = Stack.frames(heights: [60], around: h(x: 900, y: 100), in: visible)
        #expect(frames.first?.minX == 656)
    }

    @Test func staysInsideTheLeftEdgeOfADisplayAwayFromTheOrigin() {
        let side = CGRect(x: 1000, y: 100, width: 800, height: 600)
        let frames = Stack.frames(heights: [60], around: h(x: 990, y: 200), in: side)
        #expect(frames == [CGRect(x: 1004, y: 264, width: 340, height: 60)])
    }

    @Test func alignsWithTheLeftMarginOnADisplayNarrowerThanACard() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 800)
        let frames = Stack.frames(heights: [60], around: h(x: 100, y: 100), in: narrow)
        #expect(frames.first?.minX == 4)
    }

    @Test func noFramesWhenNotEvenOneCardFits() {
        let short = CGRect(x: 0, y: 0, width: 1000, height: 80)
        #expect(Stack.frames(heights: [60], around: h(x: 100, y: 12), in: short).isEmpty)
    }

    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    private func placements(_ cards: [Stack.Card], h hFrame: CGRect, isHUDVisible: Bool = true) -> [Stack.Placement] {
        Stack.placements(of: cards, around: HAnchor.Placement(frame: hFrame, displayVisibleFrame: visible),
                         isHUDVisible: isHUDVisible)
    }

    @Test func placesEachCardWithItsFrameNearestFirstClearOfTheBadge() {
        // H's top is 156; the badge reaches 10 pt above it, then the 8 pt gap.
        let placed = placements([Stack.Card(id: first, height: 60), Stack.Card(id: second, height: 80)], h: h(x: 100, y: 100))
        #expect(placed == [
            Stack.Placement(id: first, frame: CGRect(x: 100, y: 174, width: 340, height: 60)),
            Stack.Placement(id: second, frame: CGRect(x: 100, y: 242, width: 340, height: 80)),
        ])
    }

    @Test func cardsBelowHClearItsRing() {
        // H's bottom is 700; the ring reaches 6.75 pt below it, then the 8 pt gap.
        let placed = placements([Stack.Card(id: first, height: 60)], h: h(x: 100, y: 700))
        #expect(placed == [Stack.Placement(id: first, frame: CGRect(x: 100, y: 625.25, width: 340, height: 60))])
    }

    @Test func placesNothingWhileTheHUDIsHidden() {
        let placed = placements([Stack.Card(id: first, height: 60)], h: h(x: 100, y: 100), isHUDVisible: false)
        #expect(placed.isEmpty)
    }

    @Test func leavesOutCardsTheStackCannotFit() {
        let cards = [Stack.Card(id: first, height: 200), Stack.Card(id: second, height: 150), Stack.Card(id: third, height: 100)]
        #expect(placements(cards, h: h(x: 100, y: 400)).map(\.id) == [first, second])
    }
}
