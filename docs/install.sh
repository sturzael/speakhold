#!/bin/sh
# Installs Speakhold (https://speakhold.wildinteractive.app) into /Applications and opens it.
#   curl -fsSL https://speakhold.wildinteractive.app/install.sh | sh
# What it does, in order: checks this is an Apple Silicon Mac on macOS 14 or newer, downloads the latest
# release zip from GitHub, unpacks it, replaces any existing copy in /Applications (or ~/Applications if
# /Applications is not writable), clears the download flag so Gatekeeper does not block the first launch,
# and opens the app. Nothing else is touched. Source: https://github.com/sturzael/speakhold/blob/main/docs/install.sh
set -eu
ZIP_URL="https://github.com/sturzael/speakhold/releases/latest/download/Speakhold.app.zip"
say() { printf '%s\n' "$*"; }
fail() { say "Speakhold: $*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail "this installer is for macOS."
[ "$(uname -m)" = arm64 ] || fail "Speakhold needs an Apple Silicon Mac (M1 or later)."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Speakhold needs macOS 14 or newer (this Mac has $(sw_vers -productVersion))."
dest=/Applications; [ -w /Applications ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
say "Downloading the latest Speakhold..."
curl -fsSL -o "$tmp/Speakhold.app.zip" "$ZIP_URL" || fail "download failed. Check your connection and try again."
ditto -x -k "$tmp/Speakhold.app.zip" "$tmp/unpacked" || fail "could not unpack the download."
[ -d "$tmp/unpacked/Speakhold.app" ] || fail "the download did not contain Speakhold.app."
if pgrep -xq Speakhold; then say "Quitting the running copy..."; osascript -e 'tell application "Speakhold" to quit' >/dev/null 2>&1 || pkill -x Speakhold || true; sleep 1; fi
rm -rf "$dest/Speakhold.app"
ditto "$tmp/unpacked/Speakhold.app" "$dest/Speakhold.app"
xattr -dr com.apple.quarantine "$dest/Speakhold.app" 2>/dev/null || true
ver=$(defaults read "$dest/Speakhold.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")
say "Installed Speakhold ${ver} in $dest."
open -a "$dest/Speakhold.app"
say "Speakhold is in the menu bar. Hold left Control + left Option and talk. It will ask for the microphone the first time."
