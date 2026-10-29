import CoreGraphics
import Testing
@testable import HUDApp

@Suite struct PanelFrameTests {
    private let display = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    private let size = CGSize(width: 1000, height: 740)

    private func frame(hAt h: CGRect, size: CGSize? = nil, display: CGRect? = nil) -> CGRect {
        PanelController.PanelFrame.beside(
            HAnchor.Placement(frame: h, displayVisibleFrame: display ?? self.display),
            size: size ?? self.size
        )
    }

    @Test func opensToTheRightOfHWithAGap() {
        let result = frame(hAt: CGRect(x: 100, y: 1000, width: 56, height: 56))
        #expect(result.minX == 168)
        #expect(result.size == size)
    }

    @Test func topEdgeIsLevelWithHsTop() {
        let result = frame(hAt: CGRect(x: 100, y: 1000, width: 56, height: 56))
        #expect(result.maxY == 1056)
    }

    @Test func opensToTheLeftWhenTheRightSideLacksRoom() {
        let result = frame(hAt: CGRect(x: 1500, y: 1000, width: 56, height: 56))
        #expect(result.maxX == 1488)
    }

    @Test func staysRightWhenItFitsExactlyAgainstTheMargin() {
        // 920 + 56 + 12 + 1000 = 1988 = display maxX - 12
        let result = frame(hAt: CGRect(x: 920, y: 1000, width: 56, height: 56))
        #expect(result.minX == 988)
    }

    @Test func clampsIntoTheVisibleFrameWithAMargin() {
        // Too close to the left edge for either side, and too low for the top alignment.
        let result = frame(hAt: CGRect(x: 600, y: 300, width: 56, height: 56),
                           size: CGSize(width: 1000, height: 740),
                           display: CGRect(x: 0, y: 0, width: 1400, height: 1200))
        #expect(result.minX == 12)
        #expect(result.minY == 12)
    }

    @Test func clampsBelowTheTopMargin() {
        let result = frame(hAt: CGRect(x: 100, y: 1180, width: 56, height: 56))
        #expect(result.maxY == 1188)
    }

    @Test func respectsADisplayThatDoesNotStartAtTheOrigin() {
        let secondary = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let result = frame(hAt: CGRect(x: -1400, y: 1000, width: 56, height: 56), display: secondary)
        #expect(result.minX == -1332)
        #expect(result.maxY == 1056)
    }

    @Test func shrinksToFitADisplaySmallerThanThePanel() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = frame(hAt: CGRect(x: 100, y: 500, width: 56, height: 56), display: small)
        #expect(result == CGRect(x: 12, y: 12, width: 776, height: 576))
    }

    @Test func chosenSizeShrunkOnASmallDisplayComesBackInFullOnALargeOne() {
        let chosen = CGSize(width: 1200, height: 800)
        let h = CGRect(x: 100, y: 500, width: 56, height: 56)
        let small = frame(hAt: h, size: chosen, display: CGRect(x: 0, y: 0, width: 800, height: 600))
        let large = frame(hAt: h, size: chosen)
        #expect(small.size == CGSize(width: 776, height: 576))
        #expect(large.size == chosen)
    }

    @Test func placesBesideHUnclampedBeforeTheDisplayIsKnown() {
        let result = frame(hAt: CGRect(x: 100, y: 1000, width: 56, height: 56), display: .zero)
        #expect(result == CGRect(x: 168, y: 316, width: 1000, height: 740))
    }
}
