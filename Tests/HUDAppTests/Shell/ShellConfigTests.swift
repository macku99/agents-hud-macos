import Foundation
import Testing
@testable import HUDApp

@Suite struct ShellConfigTests {
    private final class Home {
        let url = FileManager.default.temporaryDirectory.appending(path: "shell-config-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)

        func write(_ json: String) {
            let folder = url.appending(path: ".config/agents-hud", directoryHint: .isDirectory)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try! Data(json.utf8).write(to: folder.appending(path: "config.json"))
        }

        func path(_ relative: String) -> String { url.appending(path: relative, directoryHint: .isDirectory).path }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @Test func withoutAFileOneDesktopRunsOnTheDefaultConfigDirectory() {
        let home = Home()
        let config = ShellConfig.load(home: home.url)
        #expect(config.desktops.map(\.name) == ["Claude"])
        #expect(config.desktops.map(\.configDirectory.path) == [home.path(".claude")])
        #expect(config.transcriptDirectories.map(\.path) == [home.path(".claude")])
    }

    @Test func readsTheDesktopsInTheirOrderAndExpandsTheTilde() {
        let home = Home()
        home.write("""
        {"desktopInstances": [{"name": "Personal", "configDirectory": "~/.claude"},
                              {"name": "Client Work", "configDirectory": "~/.claude-client"}]}
        """)
        let config = ShellConfig.load(home: home.url)
        #expect(config.desktops.map(\.name) == ["Personal", "Client Work"])
        #expect(config.desktops.map(\.configDirectory.path) == [home.path(".claude"), home.path(".claude-client")])
    }

    @Test func searchesTranscriptsInTheDefaultDirectoryThenEveryDesktopsThenTheExtraOnesOnce() {
        let home = Home()
        home.write("""
        {"desktopInstances": [{"name": "Client Work", "configDirectory": "~/.claude-client"}],
         "transcriptDirectories": ["~/.claude-cli", "~/.claude-client", "/Volumes/shared/claude"]}
        """)
        let config = ShellConfig.load(home: home.url)
        #expect(config.transcriptDirectories.map(\.path)
            == [home.path(".claude"), home.path(".claude-client"), home.path(".claude-cli"), "/Volumes/shared/claude"])
    }

    @Test func aFileWithoutDesktopsKeepsTheDefaultDesktop() {
        let home = Home()
        home.write(#"{"transcriptDirectories": ["~/.claude-cli"]}"#)
        let config = ShellConfig.load(home: home.url)
        #expect(config.desktops.map(\.name) == ["Claude"])
        #expect(config.transcriptDirectories.map(\.path) == [home.path(".claude"), home.path(".claude-cli")])
    }

    @Test func anEmptyDesktopListKeepsTheDefaultDesktop() {
        let home = Home()
        home.write(#"{"desktopInstances": []}"#)
        #expect(ShellConfig.load(home: home.url).desktops.map(\.name) == ["Claude"])
    }

    @Test func aBareTildeIsTheHomeDirectory() {
        let home = Home()
        home.write(#"{"transcriptDirectories": ["~"]}"#)
        #expect(ShellConfig.load(home: home.url).transcriptDirectories.map(\.path) == [home.path(".claude"), home.url.path])
    }

    @Test func anUnreadableFileFallsBackToTheDefaults() {
        let home = Home()
        home.write(#"{"desktopInstances": [{"name": "Personal"}]}"#)
        let config = ShellConfig.load(home: home.url)
        #expect(config.desktops.map(\.name) == ["Claude"])
        #expect(config.transcriptDirectories.map(\.path) == [home.path(".claude")])
    }
}
