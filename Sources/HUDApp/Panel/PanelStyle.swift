import AppKit
import SwiftUI

extension PanelController {
    /// The it-codex design tokens the panel draws with, in sRGB, following the system appearance.
    enum Style {
        static let bg = tone(light: 0xF5F8F5, dark: 0x07120B)
        static let panel = tone(light: 0xFCFEFD, dark: 0x0E1C13)
        static let fg = tone(light: 0x002D14, dark: 0xE0EBE3)
        static let mute = tone(light: 0x395F47, dark: 0x84988A)
        static let faint = tone(light: 0x6B8975, dark: 0x5C6E61)
        static let line = tone(light: 0xC3DBCA, dark: 0x1D2D22)
        static let accent = tone(light: 0x005129, dark: 0x63D18F)
        static let soft = tone(light: 0xC0EACD, dark: 0x0C341E)
        static let high = tone(light: 0xCF630D, dark: 0xF8A13F)
        static let danger = tone(light: 0xB63132, dark: 0xF47B74)

        static func tone(light: UInt32, dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
        }

        /// Every size the panel names is the design system's, scaled up for reading at a glance.
        static let textScale: CGFloat = 1.15

        static func sansFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
            let size = (size * textScale).rounded()
            return NSFont(name: "IBMPlexSans-\(faceName(weight))", size: size) ?? .systemFont(ofSize: size, weight: weight)
        }

        static func monoFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
            let size = (size * textScale).rounded()
            return NSFont(name: "GeistMono-\(faceName(weight))", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: weight)
        }

        static func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
            Font(sansFont(size, weight) as CTFont)
        }

        static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
            Font(monoFont(size, weight) as CTFont)
        }

        private static func faceName(_ weight: NSFont.Weight) -> String {
            switch weight {
            case .semibold: "SemiBold"
            case .medium: "Medium"
            default: "Regular"
            }
        }
    }

    /// 11 pt mono, uppercase, mute: "AGENTS", "YOU", "NEEDS INPUT".
    struct SectionLabel: View {
        let text: String

        var body: some View {
            Text(text.uppercased())
                .font(Style.mono(11, .medium))
                .foregroundStyle(Color(Style.mute))
        }
    }

    struct Hairline: View {
        var body: some View {
            Rectangle().fill(Color(Style.line)).frame(height: 1)
        }
    }

    struct MarkerView: View {
        let marker: RosterRow.Marker

        var body: some View {
            switch marker {
            case .blocked:
                RoundedRectangle(cornerRadius: 2).fill(Color(Style.high)).frame(width: 8, height: 8)
            case .unseen:
                Circle().fill(Color(Style.accent)).frame(width: 8, height: 8)
            case .working:
                Circle().fill(Color(Style.accent)).frame(width: 8, height: 8).modifier(Pulse())
            case .settled:
                Circle().strokeBorder(Color(Style.faint), lineWidth: 1).frame(width: 8, height: 8)
            }
        }
    }

    /// The only animation in the design system, for running work.
    struct Pulse: ViewModifier {
        @State private var dimmed = false

        func body(content: Content) -> some View {
            content
                .opacity(dimmed ? 0.35 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dimmed = true }
                }
        }
    }

    /// The small H in the header: fg stems, accent crossbar.
    struct HMark: View {
        var size: CGFloat = 16

        var body: some View {
            Canvas { context, canvas in
                let w = canvas.width
                let stroke = StrokeStyle(lineWidth: w * 2.6 / 24, lineCap: .round)
                var stems = Path()
                stems.move(to: CGPoint(x: w * 0.3, y: w * 0.2))
                stems.addLine(to: CGPoint(x: w * 0.3, y: w * 0.8))
                stems.move(to: CGPoint(x: w * 0.7, y: w * 0.2))
                stems.addLine(to: CGPoint(x: w * 0.7, y: w * 0.8))
                var crossbar = Path()
                crossbar.move(to: CGPoint(x: w * 0.3, y: w * 0.5))
                crossbar.addLine(to: CGPoint(x: w * 0.7, y: w * 0.5))
                context.stroke(stems, with: .color(Color(Style.fg)), style: stroke)
                context.stroke(crossbar, with: .color(Color(Style.accent)), style: stroke)
            }
            .frame(width: size, height: size)
        }
    }

    struct GhostButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            GhostLabel(configuration: configuration)
        }

        private struct GhostLabel: View {
            let configuration: ButtonStyleConfiguration
            @State private var isHovered = false

            var body: some View {
                configuration.label
                    .font(Style.mono(12))
                    .foregroundStyle(Color(Style.mute))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(Style.soft).opacity(isHovered ? 1 : 0)))
                    .contentShape(Rectangle())
                    .onHover { isHovered = $0 }
            }
        }
    }

    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Style.sans(13, .medium))
                .foregroundStyle(Color(Style.bg))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(Style.fg)))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }

    struct OutlineButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Style.mono(12))
                .foregroundStyle(Color(Style.fg))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(Style.fg), lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
