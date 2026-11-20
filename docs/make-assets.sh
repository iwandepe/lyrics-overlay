#!/usr/bin/env bash
# Regenerates docs/img/* : renders the overlay offscreen (scripted demo with placeholder lyrics),
# then composites it onto a mock desktop. Needs the app built (app/build.sh) and Pillow.
set -euo pipefail
cd "$(dirname "$0")"
FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT
LYRICS_PORT=8799 LYRICS_DATA_DIR="$FRAMES/data" LYRICS_CAPTURE="$FRAMES/frames" ../app/.build/LyricsOverlay >/dev/null 2>&1
python3 compose.py "$FRAMES/frames" img
