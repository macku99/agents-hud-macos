import CoreGraphics
import Testing
@testable import HUDApp

@Suite struct OverlayBadgeLayoutTests {
    typealias Tile = OverlayController.HTileView

    let tile = CGRect(x: 12, y: 12, width: 56, height: 56)

    @Test func pillSitsTenRightAndEightAboveTheTileCorner() {
        let pill = Tile.badgePillFrame(tileRect: tile, textWidth: 7)
        #expect(pill.maxX == tile.maxX + 10)
        #expect(pill.maxY == tile.maxY + 8)
        #expect(pill.height == 20)
    }

    @Test func pillIsAtLeastTwentyWide() {
        #expect(Tile.badgePillFrame(tileRect: tile, textWidth: 7).width == 20)
    }

    @Test func pillGrowsWithItsText() {
        #expect(Tile.badgePillFrame(tileRect: tile, textWidth: 13.2).width == 26)
    }
}

@Suite struct OverlayTileWindowTests {
    @Test func windowPaddingHoldsEverythingHDraws() {
        let overhang = OverlayController.HPosition.overhang
        let padding = OverlayController.HTileView.padding
        #expect([overhang.top, overhang.left, overhang.bottom, overhang.right].allSatisfy { $0 <= padding })
    }
}

@Suite struct OverlayTileHitTests {
    typealias Tile = OverlayController.HTileView

    let tile = CGRect(x: 12, y: 12, width: 56, height: 56)
    let badge = CGRect(x: 54, y: 52, width: 24, height: 24)

    @Test func theTileTakesTheMouse() {
        #expect(Tile.takesMouse(at: CGPoint(x: 40, y: 40), tileRect: tile, badgeFrame: nil))
    }

    @Test func aShownBadgeTakesTheMouseWhereItSticksOut() {
        #expect(Tile.takesMouse(at: CGPoint(x: 75, y: 74), tileRect: tile, badgeFrame: badge))
    }

    @Test func noBadgeLeavesThatCornerWithoutTheMouse() {
        #expect(!Tile.takesMouse(at: CGPoint(x: 75, y: 74), tileRect: tile, badgeFrame: nil))
    }

    @Test func thePaddingElsewhereDoesNotTakeTheMouse() {
        #expect(!Tile.takesMouse(at: CGPoint(x: 4, y: 4), tileRect: tile, badgeFrame: badge))
    }
}
