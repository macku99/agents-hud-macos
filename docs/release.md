# Releasing Agents HUD

A release is `Agents HUD.app` signed with the self-signed `Agents HUD Local` identity and installed into `~/Applications` on its owner's Macs. Nothing is notarized or distributed. fastlane drives it; `scripts/bundle-app.sh` does the bundling and signing.

## One-time setup

1. Create the `Agents HUD Local` signing identity as the README's [Signing identity](../README.md#signing-identity) section describes, and check `security find-identity -v -p codesigning` lists it.
2. Install the pinned fastlane:

   ```sh
   bundle config set --local path vendor/bundle
   bundle install
   ```

The first build may ask whether `codesign` may use the `Agents HUD Local` key. Choose Always Allow, or every release asks again.

## Lanes

Run every lane from the repo root with `bundle exec fastlane <lane>`.

| Lane | What it does |
|---|---|
| `test` | `swift test` over the whole package. |
| `build` | Runs `scripts/bundle-app.sh`: `swift build -c release --arch arm64`, assembles `dist/Agents HUD.app`, signs it with Hardened Runtime and runs `codesign --verify --deep --strict`. |
| `install` | Refuses unless `dist/Agents HUD.app` is signed by `Agents HUD Local`. Copies it next to the installed app, terminates a running HUD (SIGTERM to every process named `AgentsHUD`, including a development build started from `.build`), swaps the copy into `~/Applications/Agents HUD.app`, and opens it. A failed copy leaves the installed app as it was. |
| `bump` | Raises `CFBundleShortVersionString` in `Resources/Info.plist` (patch by default; `type:minor` or `type:major`) and adds 1 to `CFBundleVersion`. Commit the change yourself. |
| `release` | `ensure_git_status_clean`, then `test`, `build` and `install`, stopping at the first failure. |

A typical release, from the main checkout on an up-to-date `main`:

```sh
bundle exec fastlane bump            # or: bump type:minor
git commit -am "chore(release): bump version"
bundle exec fastlane release
```

Then run the [overlay checklist](overlay-checklist.md) on the installed app and record the results.

`install` checks the identity because macOS records Launch at login against the app's signature. Every build signed by `Agents HUD Local` carries the same designated requirement (the bundle id and that certificate), so Launch at login stays on from one release to the next. A build signed by anything else must not replace the installed app.

For a local check without the identity, `SIGNING_IDENTITY=- scripts/bundle-app.sh` builds and verifies an ad-hoc signed app in `dist/`. `install` refuses it.

`SIGNING_IDENTITY` names a different identity for `build` and `install`, either in the environment or in `fastlane/.env` (gitignored; see `fastlane/.env.example`). Unset, both use `Agents HUD Local`.

## Retiring Herdr HUD

The app was first built as Herdr HUD (`app.itfrombit.herdrhud`, executable `HerdrHUD`). `install` neither stops nor removes that app. On a Mac that still has it, quit it from its menu, delete `~/Applications/Herdr HUD.app`, and after installing Agents HUD turn on Launch at login again from the H menu, because macOS ties that setting to the bundle id.

## Manual steps

These need the owner's hands. Each ends with the check that proves it worked.

### herdr's Claude integration (needed for Chat)

Chat needs herdr to report each Claude session's id. Register herdr's `herdr-agent-state.sh`, run with its `session` action, under Claude Code's `SessionStart` hook for startup, resume, clear, compact and fork, in every Claude config directory you use.

1. Restart a Claude session in herdr for it to report its session. Check: `herdr agent get <pane>` shows `agent_session` with `kind: id`; the HUD finds the transcript by that id under `projects/*/<id>.jsonl` in `~/.claude` or a directory the [configuration](../README.md#configuration) names and shows Chat.

### Shortcuts and first launch

2. In Raycast, confirm nothing is bound to hyper+H or hyper+⇧H. Its hotkeys can't be read from files.
3. If you turn on Launch at login, approve it once under System Settings › General › Login Items.

### Testing and releases

4. Create the throwaway herdr session (`hud-test`) with a disposable agent for the opt-in integration lane, once planning confirms the setup.
5. Before each release, run the [overlay checklist](overlay-checklist.md) and record the date, macOS version and display setup.
