#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export TMPDIR="${SUBLER_BUILD_SCRATCH:-$HOME/.hermes/cache/scratch}"
mkdir -p "$TMPDIR" dist
OPTIONS=()
if [[ "${SUBLER_BUILD_LOCAL_ENGINE:-0}" == 1 ]]; then
  APP="${SUBLER_BUILD_APP:-$PWD/dist-local/Subler Automation Local.app}"
  OPTIONS+=(--local-engine)
else
  APP="${SUBLER_BUILD_APP:-$PWD/dist/Subler Automation.app}"
fi
python3 scripts/configure-app-bundle.py --app "$APP" "${OPTIONS[@]}" --check-only
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SublerAutomation" "$APP/Contents/MacOS/SublerAutomation"
cp Sources/SublerAutomation/Resources/Info.plist "$APP/Contents/Info.plist"
python3 scripts/configure-app-bundle.py --app "$APP" "${OPTIONS[@]}"
swift scripts/make-icon.swift "$TMPDIR/SublerAutomation.iconset"
iconutil -c icns "$TMPDIR/SublerAutomation.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nApplication compilée : %s\n' "$APP"
