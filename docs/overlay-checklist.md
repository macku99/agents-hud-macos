# Overlay checklist

Run this by hand before every release, on the build `fastlane install` just put into `~/Applications`. The H tile, the panel and the alerts are all floating windows, and no automated test can show how macOS draws and routes input to them over fullscreen apps, other displays, Stage Manager or Mission Control.

Rule: a scenario you did not run is recorded as **not run**. It is never reported as pass, and a release note may only call an overlay behaviour verified if its row says pass for that release.

## Scenarios

Each scenario passes only if every check under it holds.

### 1. Native fullscreen Spaces and switching Spaces

- Put an app into native fullscreen (green button or ⌃⌘F). H stays visible on top of it.
- Click H. The panel opens beside H over the fullscreen app, and typing in the prompt box works.
- Switch Spaces with ⌃← / ⌃→ and with a trackpad swipe, between a desktop and a fullscreen Space in both directions. H is on top after every switch, without clicking anything.
- With an alert showing, switch Spaces. The alert stays anchored to H.

### 2. Multiple displays

- **Per-display position.** Drag H to a different spot on each display, quit and relaunch the HUD. H comes back at the saved spot on each display.
- **Fullscreen on one display.** Fullscreen an app on display A while display B shows a desktop. H is on top on both, and the panel opens next to H on whichever display it is on.
- **Hot-plugging a display.** Unplug a display H was on, then plug it back in. H moves to a visible spot while the display is gone and returns to its saved position on that display when it is back. No window is left off-screen.

### 3. Stage Manager

- Turn Stage Manager on. H stays on top of the centre stage and is not swallowed into a stage set.
- Switch stage sets. H stays visible, and the panel opens and takes input.

### 4. Mission Control

- Open Mission Control (F3 or a swipe up). Note whether H is shown, then close it. H is on top again and responds to a click.
- Open App Exposé on the frontmost app and close it. Same checks.

### 5. Games and exclusive fullscreen

**PERMANENTLY UNVERIFIED. Not tested.** Games and apps that take exclusive control of the display are outside what the HUD promises. Always record this row as not run.

## Record

For each release, copy the seven template rows below to the bottom of the record table, fill in date, HUD version, macOS version and display setup, and change a result from `not run` only for scenarios you actually ran. Never edit rows from an earlier release; a re-run gets new rows.

- **Date:** YYYY-MM-DD.
- **HUD version:** CFBundleShortVersionString (CFBundleVersion), e.g. `0.1.0 (1)`.
- **macOS version:** from `sw_vers`, e.g. `27.0 (26A123)`.
- **Display setup:** e.g. "MacBook built-in + 27-inch external on the left".
- **Result:** `pass`, `fail` or `not run`.

Template rows:

```
| | | | | 1. Fullscreen Spaces | not run | |
| | | | | 2. Multiple displays: per-display position | not run | |
| | | | | 2. Multiple displays: fullscreen on one display | not run | |
| | | | | 2. Multiple displays: hot-plugging | not run | |
| | | | | 3. Stage Manager | not run | |
| | | | | 4. Mission Control | not run | |
| | | | | 5. Games / exclusive fullscreen | not run | permanently unverified |
```

| Date | HUD version | macOS version | Display setup | Scenario | Result | Notes |
|---|---|---|---|---|---|---|
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 1. Fullscreen Spaces | not run | Not a release run. M saw H stay on top over a fullscreen app and across Space switches; the panel over a fullscreen app and an alert during a switch were not checked separately. |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 2. Multiple displays: per-display position | not run | |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 2. Multiple displays: fullscreen on one display | not run | |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 2. Multiple displays: hot-plugging | not run | |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 3. Stage Manager | not run | |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 4. Mission Control | not run | |
| 2026-10-23 | dev build, unbundled (pre-release) | 27.2 (26B118) | built-in + external | 5. Games / exclusive fullscreen | not run | permanently unverified |
