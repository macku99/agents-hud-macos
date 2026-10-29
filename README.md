# Agents HUD for macOS

A native menu-bar app that keeps a floating H button above every Space, including fullscreen ones. The button opens a panel listing the agents running in [herdr](https://herdr.dev) on this Mac, with each Claude Code agent's recent conversation (or any agent's screen text) and a prompt box for follow-ups. Questions and approvals an agent is waiting on are answered in herdr; the HUD takes you there.

The same roster lists the Claude Code sessions running in Claude Desktop. The HUD reads the status file each session's process keeps in its Claude config directory and shows the session's conversation from its transcript. A Desktop session takes no prompts from the HUD; its row's button brings Claude Desktop forward.

It is built for one person's Macs: Apple Silicon, macOS 27.

## Configuration

`~/.config/agents-hud/config.json` names the Claude Desktop instances the roster lists, each with the Claude config directory its sessions use, and any further config directories to look for transcripts in. The app reads it at launch:

```json
{
  "desktopInstances": [
    { "name": "Personal", "configDirectory": "~/.claude" },
    { "name": "Work", "configDirectory": "~/.claude-work" }
  ],
  "transcriptDirectories": ["~/.claude-cli"]
}
```

Paths are absolute or start with `~/`, and each instance needs a name of its own. Without the file, with one it cannot read, or with no instances in it, the HUD lists one instance, Claude, on `~/.claude`. Transcripts are always looked up in `~/.claude` as well.

## Development

```sh
swift build   # builds every target
swift test    # runs every test target; no test talks to a real herdr
```

Run the development build detached, so it outlives the shell that started it, and quit it from the H menu in the menu bar:

```sh
nohup "$(swift build --show-bin-path)/AgentsHUD" >/dev/null 2>&1 &
```

The app writes send attempts and failed herdr calls to the unified log, never prompt text. In zsh, `log` is a builtin, so call the tool by its path:

```sh
/usr/bin/log stream --predicate 'subsystem == "app.itfrombit.agentshud"'
```

Release builds, signed with the identity below and installed into `~/Applications`, come from fastlane; see `docs/release.md`.

| Target | Owns |
|---|---|
| `HerdrKit` | herdr's vocabulary and the transport to it (CLI and socket) |
| `HerdrKitTesting` | `FakeHerdr`, the scriptable client every test uses |
| `HUDCore` | `HUDStore`: roster, attention, alerts, drafts, sending; `AgentSource` and herdr's source |
| `DesktopSessions` | the Claude Desktop instances' sessions, read from their status files |
| `Transcript` | Claude Code transcripts turned into chat blocks |
| `HUDApp` | windows and system integration: overlay, panel, shell |
| `AgentsHUD` | the executable |

## Signing identity

Release builds are signed with a self-signed certificate named `Agents HUD Local` in the login keychain. The app is only ever installed on its owner's Macs, so nothing needs Apple's trust: there is no Gatekeeper check to pass and nothing to notarize. What the build does need is a signature that stays the same from one build to the next, because macOS ties Launch at login to it. An ad-hoc signature changes with every build, and an Apple Development certificate expires each year, belongs to a team, and can change what macOS sees when it is renewed. A self-signed certificate lasts as long as you choose and depends on no Apple account.

Create it once in Keychain Access, then move it to any other Mac as described below:

1. With Keychain Access in front, open the Keychain Access menu in the menu bar (next to the Apple menu, not inside the window) and choose Certificate Assistant › Create a Certificate.
2. Name it `Agents HUD Local`, set Identity Type to Self Signed Root and Certificate Type to Code Signing, and tick "Let me override defaults".
3. Continue, set the validity period to `3650` days, keep the other defaults, and save it to the login keychain.
4. Open the certificate under login › My Certificates. In its Trust section set Code Signing to Always Trust, then close it and enter your password.

Then check that macOS offers it for code signing:

```sh
security find-identity -v -p codesigning   # lists "Agents HUD Local"
```

Other Macs will not trust this certificate, which is fine for an app that never leaves its owner's machines. To move the identity to another Mac, export it with its private key as a `.p12` from Keychain Access and import it there, rather than creating a new one: a new certificate is a new signature, and Launch at login has to be turned on again.

## License

MIT; see [LICENSE](LICENSE).
