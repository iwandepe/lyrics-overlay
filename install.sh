#!/usr/bin/env bash
# Installs Lyrics Overlay:   curl -fsSL https://raw.githubusercontent.com/iwandepe/lyrics-overlay/main/install.sh | bash
# Remove it:                 curl -fsSL .../install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="${LYRICS_OVERLAY_REPO:-iwandepe/lyrics-overlay}"    # keep in sync with Config.swift
APP_NAME="Lyrics Overlay"
ZIP_URL="${LYRICS_OVERLAY_ZIP_URL:-https://github.com/$REPO/releases/latest/download/LyricsOverlay.zip}"
DEST_DIR="${LYRICS_OVERLAY_INSTALL_DIR:-/Applications}"

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Lyrics Overlay is for macOS."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || die "Needs macOS 13 (Ventura) or newer."

# Only quits an installed copy (…/Lyrics Overlay.app/…), never a development build.
quit_app() { pkill -f "/$APP_NAME.app/Contents/MacOS/LyricsOverlay" 2>/dev/null && sleep 1 || true; }

if [ "${1:-}" = "--uninstall" ]; then
  quit_app
  for d in "$DEST_DIR" "$HOME/Applications"; do rm -rf "$d/$APP_NAME.app"; done
  say "Removed $APP_NAME. Your saved sync fixes remain in ~/Library/Application Support/LyricsOverlay (delete it to remove them)."
  say "Also remove the browser extension in Zen/Firefox: Add-ons → Lyrics Overlay Bridge → Remove."
  exit 0
fi

[[ -n "${LYRICS_OVERLAY_ZIP_URL:-}" || "$REPO" != OWNER/* ]] || die "This installer isn't configured with a GitHub repository yet."

# Install into /Applications, or ~/Applications when that isn't writable.
if [ ! -w "$DEST_DIR" ]; then DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "Downloading ${APP_NAME}…"
curl -fL --progress-bar -o "$TMP/app.zip" "$ZIP_URL" || die "Download failed: $ZIP_URL"

if curl -fsL -o "$TMP/app.zip.sha256" "$ZIP_URL.sha256" 2>/dev/null; then
  want="$(awk '{print $1}' "$TMP/app.zip.sha256")"; got="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [ "$want" = "$got" ] || die "Checksum mismatch; the download is corrupted. Nothing was installed."
fi

ditto -x -k "$TMP/app.zip" "$TMP/out"
[ -d "$TMP/out/$APP_NAME.app" ] || die "The download didn't contain $APP_NAME.app."

quit_app
rm -rf "$DEST_DIR/$APP_NAME.app"
mv "$TMP/out/$APP_NAME.app" "$DEST_DIR/"
# curl downloads aren't quarantined, but clear the flag in case a mirror or browser added it.
xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

say "Installed to $DEST_DIR/$APP_NAME.app"
[ -n "${LYRICS_OVERLAY_NO_LAUNCH:-}" ] || open "$DEST_DIR/$APP_NAME.app"
say "A setup guide opens on first launch. It will help you add the browser extension."
