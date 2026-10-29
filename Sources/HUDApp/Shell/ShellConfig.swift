import DesktopSessions
import Foundation
import os

private let configLog = Logger(subsystem: "app.itfrombit.agentshud", category: "config")

/// The Claude Desktop instances the roster lists and the Claude config directories transcripts are
/// looked up in, read from `~/.config/agents-hud/config.json`:
///
///     {"desktopInstances": [{"name": "Personal", "configDirectory": "~/.claude"}],
///      "transcriptDirectories": ["~/.claude-cli"]}
///
/// Without the file, or with one that cannot be decoded, the HUD lists one instance on `~/.claude`.
struct ShellConfig {
    let desktops: [DesktopInstance]
    /// Always includes `~/.claude`, which holds every session started without CLAUDE_CONFIG_DIR, then
    /// each desktop's directory and the extra ones, each directory once.
    let transcriptDirectories: [URL]

    private struct File: Decodable {
        struct Desktop: Decodable {
            let name: String
            let configDirectory: String
        }

        let desktopInstances: [Desktop]?
        let transcriptDirectories: [String]?
    }

    static func load(home: URL) -> ShellConfig {
        let url = home.appending(path: ".config/agents-hud/config.json")
        var file = File(desktopInstances: nil, transcriptDirectories: nil)
        do {
            file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            configLog.error("Ignoring \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        let defaultDirectory = home.appending(path: ".claude", directoryHint: .isDirectory)
        let entries = file.desktopInstances ?? []
        let desktops = entries.isEmpty
            ? [DesktopInstance(name: "Claude", configDirectory: defaultDirectory)]
            : entries.map { DesktopInstance(name: $0.name, configDirectory: directory($0.configDirectory, home: home)) }
        let extras = (file.transcriptDirectories ?? []).map { directory($0, home: home) }

        var seen: Set<String> = []
        let transcripts = ([defaultDirectory] + desktops.map(\.configDirectory) + extras).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
        return ShellConfig(desktops: desktops, transcriptDirectories: transcripts)
    }

    private static func directory(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2)), directoryHint: .isDirectory) }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
