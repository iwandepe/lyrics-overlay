#!/usr/bin/env bash
# Rehearses the self-update flow end to end against a local fake "GitHub releases" server:
# installed v0.1.0 should accept a correctly signed v0.2.0, and refuse tampered / wrongly signed /
# mismatched downloads. Uses your real signing key (the app only trusts that key).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEY="${LYRICS_SIGNING_KEY:-$HOME/.config/lyrics-overlay/signing.key}"
PORT=8123
BID=com.lyricsoverlay.app
T="$(mktemp -d)"
mkdir -p "$T/srv" "$T/Applications"

cleanup() {
  pkill -f "$T/Applications" 2>/dev/null || true
  [ -n "${SERVER:-}" ] && kill "$SERVER" 2>/dev/null || true
  defaults delete "$BID" didOnboard 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT
defaults write "$BID" didOnboard -bool true          # keep the setup guide out of the test

source "$ROOT/app/_env.sh"
swiftc -O "${SWIFTC_FLAGS[@]}" -o "$ROOT/app/.build/sign-release" "$ROOT/app/tools/sign-release.swift"
SIGN="$ROOT/app/.build/sign-release"
OTHERKEY="$T/other.key"; "$SIGN" gen "$OTHERKEY" >/dev/null

build_zip() {   # version, out.zip
  VERSION="$1" "$ROOT/app/make-app.sh" >/dev/null
  ditto -c -k --keepParent "$ROOT/app/build/Lyrics Overlay.app" "$2"
}
write_feed() {  # case-dir, tag, zip-name
  cat > "$1/latest.json" <<JSON
{"tag_name":"$2","body":"Rehearsal release","draft":false,"prerelease":false,"assets":[
 {"name":"LyricsOverlay.zip","browser_download_url":"http://127.0.0.1:$PORT/$(basename "$1")/LyricsOverlay.zip"},
 {"name":"LyricsOverlay.zip.sig","browser_download_url":"http://127.0.0.1:$PORT/$(basename "$1")/LyricsOverlay.zip.sig"}]}
JSON
}

echo "• building v0.1.0 (installed), v0.2.0 (valid update), v0.3.0 (for the mismatch case)"
VERSION=0.3.0 build_zip 0.3.0 "$T/v3.zip"
build_zip 0.2.0 "$T/v2.zip"
build_zip 0.1.0 "$T/v1.zip"
ditto -x -k "$T/v1.zip" "$T/v1app"

mkdir -p "$T/srv/ok" "$T/srv/tampered" "$T/srv/wrongkey" "$T/srv/mismatch"
cp "$T/v2.zip" "$T/srv/ok/LyricsOverlay.zip";        "$SIGN" sign "$KEY" "$T/v2.zip" > "$T/srv/ok/LyricsOverlay.zip.sig";        write_feed "$T/srv/ok" v0.2.0 x
cp "$T/v2.zip" "$T/srv/tampered/LyricsOverlay.zip";  printf 'x' >> "$T/srv/tampered/LyricsOverlay.zip"
"$SIGN" sign "$KEY" "$T/v2.zip" > "$T/srv/tampered/LyricsOverlay.zip.sig";                                                       write_feed "$T/srv/tampered" v0.2.0 x
cp "$T/v2.zip" "$T/srv/wrongkey/LyricsOverlay.zip";  "$SIGN" sign "$OTHERKEY" "$T/v2.zip" > "$T/srv/wrongkey/LyricsOverlay.zip.sig"; write_feed "$T/srv/wrongkey" v0.2.0 x
cp "$T/v3.zip" "$T/srv/mismatch/LyricsOverlay.zip";  "$SIGN" sign "$KEY" "$T/v3.zip" > "$T/srv/mismatch/LyricsOverlay.zip.sig";  write_feed "$T/srv/mismatch" v0.2.0 x

( cd "$T/srv" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & SERVER=$!
sleep 1

APP="$T/Applications/Lyrics Overlay.app"
ver() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "?"; }
failures=0

run_case() {  # name, expected version after, expected log text ("" = none)
  local name="$1" want="$2" logwant="$3"
  pkill -f "$T/Applications" 2>/dev/null || true; sleep 0.5
  rm -rf "$APP" "$T"/Applications/.LyricsOverlay-update-*; ditto "$T/v1app/Lyrics Overlay.app" "$APP"
  LYRICS_UPDATE_FEED="http://127.0.0.1:$PORT/$name/latest.json" LYRICS_UPDATE_AUTOINSTALL=1 \
  LYRICS_PORT=8799 LYRICS_DATA_DIR="$T/data" \
    "$APP/Contents/MacOS/LyricsOverlay" > "$T/$name.log" 2>&1 &
  for _ in $(seq 1 50); do
    sleep 0.5
    [ "$(ver)" = "$want" ] && [ "$want" != "0.1.0" ] && break
    [ -n "$logwant" ] && grep -q "$logwant" "$T/$name.log" && break
  done
  sleep 2
  local got; got="$(ver)"; local ok=1
  [ "$got" = "$want" ] || ok=0
  [ -z "$logwant" ] || grep -q "$logwant" "$T/$name.log" || ok=0
  ls "$T"/Applications/.LyricsOverlay-update-* >/dev/null 2>&1 && { echo "   leftover staging folder!"; ok=0; }
  if [ "$want" != "0.1.0" ]; then pgrep -f "$APP/Contents/MacOS/LyricsOverlay" >/dev/null || { echo "   app did not relaunch"; ok=0; }; fi
  if [ $ok = 1 ]; then echo "  ✓ $name: installed version is $got"; else echo "  ✗ $name: version $got (wanted $want), log: $(tr '\n' ' ' < "$T/$name.log")"; failures=$((failures+1)); fi
}

echo "• running cases"
run_case ok        0.2.0 ""
run_case tampered  0.1.0 "signature is invalid"
run_case wrongkey  0.1.0 "signature is invalid"
run_case mismatch  0.1.0 "didn't match what was announced"
[ $failures = 0 ] && echo "ALL UPDATE CASES PASSED" || { echo "$failures CASE(S) FAILED"; exit 1; }
