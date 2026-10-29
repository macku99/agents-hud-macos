import AppKit
import Testing
@testable import HUDApp

/// H floats over any window or wallpaper, whatever the system appearance, so its working ring has to
/// stand out against light and dark content alike.
@Suite @MainActor struct OverlayRingContrastTests {
    typealias Style = OverlayController.Style

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua],
          [("white", 0xFFFFFF), ("sky", 0xC9DDF0), ("light panel", 0xF5F8F5), ("dark panel", 0x07120B), ("black", 0x000000)])
    func theWorkingRingMeetsNonTextContrastOnAnyBackground(appearance: NSAppearance.Name, background: (String, UInt32)) throws {
        let ring = try #require(srgb(Style.ring, in: appearance))
        #expect(contrast(ring, background.1) >= 3, "against \(background.0)")
    }

    private func srgb(_ color: NSColor, in name: NSAppearance.Name) -> NSColor? {
        var resolved: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        return resolved
    }

    private func contrast(_ color: NSColor, _ hex: UInt32) -> Double {
        let background = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                 blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        let (a, b) = (luminance(color), luminance(background))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: NSColor) -> Double {
        func linear(_ c: CGFloat) -> Double { c <= 0.03928 ? Double(c) / 12.92 : pow((Double(c) + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }
}
