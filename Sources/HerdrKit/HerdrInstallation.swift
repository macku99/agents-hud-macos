import Foundation

/// Where the local herdr lives and how its CLI is run. The app may start from launchd with no shell
/// environment, and an inherited `HERDR_*` variable could point the CLI at another server, so neither
/// PATH nor the parent environment is trusted.
enum HerdrInstallation {
    static func binaryCandidates(home: String) -> [String] {
        ["\(home)/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
    }

    static func binary(home: String, isExecutable: (String) -> Bool) -> String? {
        binaryCandidates(home: home).first(where: isExecutable)
    }

    static func childEnvironment(parent: [String: String], home: String) -> [String: String] {
        var environment = parent.filter { !$0.key.hasPrefix("HERDR_") }
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    /// The path on the `socket: <path>` line of `herdr status server`.
    static func socketPath(inServerStatus output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("socket:") else { continue }
            let path = line.dropFirst("socket:".count).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
        return nil
    }
}
