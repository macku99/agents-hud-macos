#!/usr/bin/env bash
# Builds the release binary and wraps it into a signed "dist/Agents HUD.app".
#
# SIGNING_IDENTITY is the codesign identity, normally the self-signed "Agents HUD Local"
# (see README.md). "-" signs ad hoc, which is only good for local checks: an ad-hoc
# signature changes with every build, and macOS records Launch at login against it.
set -euo pipefail

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "error: SIGNING_IDENTITY is not set." >&2
  echo "Set it to the signing identity, e.g. \"Agents HUD Local\" (see 'security find-identity -v -p codesigning')," >&2
  echo "or to '-' for an ad-hoc build used only for local checks." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app="dist/Agents HUD.app"

swift build -c release --arch arm64
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/AgentsHUD" "$app/Contents/MacOS/AgentsHUD"
cp "Resources/Info.plist" "$app/Contents/Info.plist"

# A secure timestamp comes from Apple's timestamp server and only matters for notarization,
# which a build installed only on its owner's Macs never goes through.
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"

echo "Built and verified $repo_root/$app"
