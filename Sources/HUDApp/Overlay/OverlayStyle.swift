import AppKit

extension OverlayController {
    /// The it-codex colours and type the overlay draws with, following the system appearance.
    enum Style {
        static let bg = color(light: 0xF5F8F5, dark: 0x07120B)
        static let fg = color(light: 0x002D14, dark: 0xE0EBE3)
        static let mute = color(light: 0x395F47, dark: 0x84988A)
        static let faint = color(light: 0x6B8975, dark: 0x5C6E61)
        static let line = color(light: 0xC3DBCA, dark: 0x1D2D22)
        static let accent = color(light: 0x005129, dark: 0x63D18F)
        static let high = color(light: 0xCF630D, dark: 0xF8A13F)
        /// The working ring around H, in both appearances: H floats over any window or wallpaper, so the
        /// appearance says nothing about what is behind it. A mid green clears 3:1 on white and on near-black.
        static let ring = color(light: 0x1F8A4C, dark: 0x1F8A4C)
        /// The unread badge on H, in both appearances: light green, with a British racing green border and count.
        static let badgeFill = color(light: 0x63D18F, dark: 0x63D18F)
        static let badgeBorder = color(light: 0x004225, dark: 0x004225)

        static func mono(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            NSFont(name: "GeistMono-" + faceSuffix(weight), size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: weight)
        }

        static func sans(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            NSFont(name: "IBMPlexSans-" + faceSuffix(weight), size: size)
                ?? .systemFont(ofSize: size, weight: weight)
        }

        private static func faceSuffix(_ weight: NSFont.Weight) -> String {
            switch weight {
            case .semibold: "SemiBold"
            case .medium: "Medium"
            default: "Regular"
            }
        }

        private static func color(light: UInt32, dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
        }
    }
}
