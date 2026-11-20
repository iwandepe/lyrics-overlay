#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) "Lyrics Overlay.app" into app/build/.
# Ad-hoc signed (no Apple Developer account needed). VERSION comes from ../VERSION (override: VERSION=1.2.3).
set -euo pipefail
cd "$(dirname "$0")"
source ./_env.sh

VERSION="${VERSION:-$(tr -d '[:space:]' < ../VERSION)}"
BUNDLE_ID="com.lyricsoverlay.app"     # keep stable: login items, saved settings and updates are tied to it
APP="build/Lyrics Overlay.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/arch

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macosx13.0" "${SWIFTC_FLAGS[@]}" \
    -o "build/arch/LyricsOverlay-$arch" Sources/LyricsOverlay/*.swift
done
lipo -create -output "$APP/Contents/MacOS/LyricsOverlay" build/arch/LyricsOverlay-arm64 build/arch/LyricsOverlay-x86_64
rm -rf build/arch

[ -f Resources/AppIcon.icns ] || python3 make-icon.py
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lyrics Overlay</string>
  <key>CFBundleDisplayName</key><string>Lyrics Overlay</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>LyricsOverlay</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (v$VERSION, $(lipo -archs "$APP/Contents/MacOS/LyricsOverlay"))"
