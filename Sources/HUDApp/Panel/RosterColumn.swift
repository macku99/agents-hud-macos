import HUDCore
import SwiftUI

extension PanelController {
    struct RosterColumn: View {
        let store: HUDStore

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SectionLabel(text: "agents")
                    Text("\(store.roster.count)").font(Style.mono(12)).foregroundStyle(Color(Style.faint))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                Hairline()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.roster) { entry in
                            RosterRowView(entry: entry, isSelected: entry.id == store.selectedAgent) {
                                store.select(entry.id)
                            }
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    /// Drag to resize the roster; the width is remembered when the drag ends.
    struct RosterDivider: View {
        @Binding var width: CGFloat
        let preference: RosterWidth
        @State private var dragStart: CGFloat?

        var body: some View {
            ZStack {
                Rectangle().fill(Color(Style.line)).frame(width: 1)
                RoundedRectangle(cornerRadius: 2).fill(Color(Style.line)).frame(width: 4, height: 28)
            }
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? width
                        dragStart = start
                        width = RosterWidth.clamped(start + drag.translation.width)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        preference.store(width)
                    }
            )
        }
    }
}

extension PanelController {
    fileprivate struct RosterRowView: View {
        let entry: RosterEntry
        let isSelected: Bool
        let select: () -> Void
        @State private var isHovered = false

        var body: some View {
            Group {
                if entry.agent.status == .working {
                    TimelineView(.periodic(from: .now, by: 1)) { context in content(now: context.date) }
                } else {
                    content(now: .now)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(Color(Style.accent)).frame(width: 2).padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: select)
        }

        private var background: Color {
            if isSelected { return Color(Style.panel) }
            return isHovered ? Color(Style.soft) : .clear
        }

        private func content(now: Date) -> some View {
            let row = RosterRow(entry, now: now, time: TimeText())
            return VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.title)
                    .font(Style.sans(15, .medium))
                    .foregroundStyle(Color(Style.fg))
                    .lineLimit(1)
                Text(verbatim: row.meta)
                    .font(Style.mono(12))
                    .foregroundStyle(Color(Style.faint))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MarkerView(marker: row.marker)
                    Text(verbatim: row.stateLine)
                        .font(Style.mono(11))
                        .foregroundStyle(Color(Style.mute))
                        .lineLimit(1)
                }
            }
        }
    }
}
