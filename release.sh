#!/usr/bin/env bash
# Builds everything to attach to a GitHub release, into dist/:
#   LyricsOverlay.zip, LyricsOverlay.zip.sha256, LyricsOverlay.zip.sig   (app + its update signature)
#   lyrics-overlay-bridge-<version>-unsigned.zip                          (extension, to sign on addons.mozilla.org)
# Nothing is published: this only prepares files and prints the next steps.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
KEY="${LYRICS_SIGNING_KEY:-$HOME/.config/lyrics-overlay/signing.key}"
grep -q 'githubRepo = "OWNER/' app/Sources/LyricsOverlay/Config.swift && {
  echo "Set githubRepo in app/Sources/LyricsOverlay/Config.swift to your GitHub owner/repo first."; exit 1; }
[ -f "$KEY" ] || { echo "Signing key not found at $KEY"; exit 1; }

source app/_env.sh
swiftc -O "${SWIFTC_FLAGS[@]}" -o app/.build/sign-release app/tools/sign-release.swift
EMBEDDED="$(sed -n 's/.*publicKeyBase64 = "\(.*\)".*/\1/p' app/Sources/LyricsOverlay/UpdateCore.swift)"
[ "$(app/.build/sign-release pub "$KEY")" = "$EMBEDDED" ] || {
  echo "The signing key at $KEY doesn't match the public key embedded in the app. Installed copies would reject this update."; exit 1; }

app/run-tests.sh | tail -1
app/make-app.sh

rm -rf dist && mkdir -p dist
ditto -c -k --keepParent "app/build/Lyrics Overlay.app" dist/LyricsOverlay.zip
( cd dist && shasum -a 256 LyricsOverlay.zip > LyricsOverlay.zip.sha256 )
app/.build/sign-release sign "$KEY" dist/LyricsOverlay.zip > dist/LyricsOverlay.zip.sig

# Extension: stamp the same version, zip only the files Firefox needs.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp extension/manifest.json extension/background.js extension/content.js "$STAGE"/
[ -d extension/icons ] && cp -R extension/icons "$STAGE"/
sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$STAGE/manifest.json"
( cd "$STAGE" && zip -qr "$OLDPWD/dist/lyrics-overlay-bridge-$VERSION-unsigned.zip" . )

echo
echo "Release $VERSION is ready in dist/:"; ls -1 dist | sed 's/^/  /'
cat <<NEXT

Next steps (nothing has been published):
  1. Sign the extension: upload dist/lyrics-overlay-bridge-$VERSION-unsigned.zip at
     https://addons.mozilla.org/developers/ (choose "On your own" = unlisted), download the signed .xpi,
     and rename it to lyrics-overlay-bridge.xpi.
  2. Create the release and attach the files:
       gh release create v$VERSION dist/LyricsOverlay.zip dist/LyricsOverlay.zip.sha256 \\
         dist/LyricsOverlay.zip.sig lyrics-overlay-bridge.xpi --title "v$VERSION" --notes "What changed"
NEXT
