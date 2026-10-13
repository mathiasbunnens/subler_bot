#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export TMPDIR="${SUBLER_BUILD_SCRATCH:-$HOME/.hermes/cache/scratch}"
mkdir -p "$TMPDIR" dist
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="${SUBLER_BUILD_APP:-$PWD/dist/Subler Automation.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SublerAutomation" "$APP/Contents/MacOS/SublerAutomation"
cp Sources/SublerAutomation/Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$TMPDIR/SublerAutomation.iconset"
iconutil -c icns "$TMPDIR/SublerAutomation.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nApplication compilée : %s\n' "$APP"
