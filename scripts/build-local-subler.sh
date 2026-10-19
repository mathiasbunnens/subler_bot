#!/bin/bash
# Local experimental build only; never installs or replaces /Applications/Subler.app.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${LOCAL_SUBLER_BUILD_ROOT:?Set an absolute scratch build root}"
case "$LOCAL_SUBLER_BUILD_ROOT" in /*) ;; *) exit 2 ;; esac
source_root="$PWD/vendor-local/Subler"
if [ ! -f "$source_root/Subler.xcodeproj/project.pbxproj" ]; then
    printf '%s\n' 'Prepare the pinned checkout described in docs/local-subler-background.md first.' >&2
    exit 2
fi
mkdir -p "$LOCAL_SUBLER_BUILD_ROOT"
xcodebuild -project "$source_root/Subler.xcodeproj" -scheme Subler -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$LOCAL_SUBLER_BUILD_ROOT" \
    CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
    PRODUCT_BUNDLE_IDENTIFIER=local.sublerautomation.Subler build > "$LOCAL_SUBLER_BUILD_ROOT/build.log" 2>&1
app="$LOCAL_SUBLER_BUILD_ROOT/Build/Products/Release/Subler.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Subler Automation Local' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SublerAutomationBackgroundProtocol string 1' "$app/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Set :SublerAutomationBackgroundProtocol 1' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :LSUIElement' "$app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :LSBackgroundOnly bool true' "$app/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Set :LSBackgroundOnly true' "$app/Contents/Info.plist"
# Automatic upstream updates must never replace this separately reviewed build.
/usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "$app/Contents/Info.plist" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
