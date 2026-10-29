import Testing
@testable import HerdrKit

@Suite struct TransportInstallationTests {
    @Test func prefersTheUserLocalBinaryOverHomebrewAndUsrLocal() {
        let everywhere: (String) -> Bool = { _ in true }
        #expect(HerdrInstallation.binary(home: "/Users/me", isExecutable: everywhere) == "/Users/me/.local/bin/herdr")
    }

    @Test func fallsBackThroughTheCandidatesInOrder() {
        let installed: Set = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        #expect(HerdrInstallation.binary(home: "/Users/me", isExecutable: installed.contains) == "/opt/homebrew/bin/herdr")
        #expect(HerdrInstallation.binary(home: "/Users/me", isExecutable: { $0 == "/usr/local/bin/herdr" }) == "/usr/local/bin/herdr")
    }

    @Test func noCandidateMeansNotInstalled() {
        #expect(HerdrInstallation.binary(home: "/Users/me", isExecutable: { _ in false }) == nil)
    }

    @Test func childEnvironmentDropsEveryHerdrVariableAndFixesPath() {
        let parent = ["HOME": "/Users/me", "HERDR_SOCKET": "/x.sock", "HERDR_PANE_ID": "w1:p1", "PATH": "/evil/bin",
                      "LANG": "en_US.UTF-8", "MY_HERDR_NOTE": "kept"]
        let child = HerdrInstallation.childEnvironment(parent: parent, home: "/Users/me")
        #expect(child == ["HOME": "/Users/me", "LANG": "en_US.UTF-8", "MY_HERDR_NOTE": "kept",
                          "PATH": "/Users/me/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"])
    }

    @Test func readsTheSocketPathFromServerStatus() {
        let status = """
        status: running
        version: 0.9.5
        private_protocol: 22
        socket: /Users/me/.config/herdr/herdr.sock
        """
        #expect(HerdrInstallation.socketPath(inServerStatus: status) == "/Users/me/.config/herdr/herdr.sock")
    }

    @Test func socketPathToleratesExtraSpacesAndKeepsInnerSpaces() {
        #expect(HerdrInstallation.socketPath(inServerStatus: "socket:   /tmp/my dir/h.sock  \n") == "/tmp/my dir/h.sock")
    }

    @Test func statusWithoutASocketLineHasNoPath() {
        #expect(HerdrInstallation.socketPath(inServerStatus: "status: stopped\nversion: 0.9.5\n") == nil)
        #expect(HerdrInstallation.socketPath(inServerStatus: "socket:\n") == nil)
        #expect(HerdrInstallation.socketPath(inServerStatus: "private_socket: /x.sock\n") == nil)
    }
}
