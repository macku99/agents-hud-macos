import Foundation

extension PanelController {
    /// Which tool groups M has expanded, by block id, so a transcript re-read keeps them open.
    struct ToolGroupExpansion {
        private var expanded: Set<String> = []

        func isExpanded(_ id: String) -> Bool { expanded.contains(id) }

        mutating func toggle(_ id: String) {
            if expanded.remove(id) == nil { expanded.insert(id) }
        }
    }

    enum ChatText {
        static func turnMeta(duration: Duration, at: Date?, time: TimeText) -> String {
            ["worked for \(time.duration(duration))", at.map(time.clock)].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
