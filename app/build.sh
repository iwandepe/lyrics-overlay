#!/usr/bin/env bash
# Dev build (current architecture, unbundled): .build/LyricsOverlay. For a distributable .app use make-app.sh.
set -euo pipefail
cd "$(dirname "$0")"
source ./_env.sh
swiftc -O -target "$(uname -m)-apple-macosx13.0" "${SWIFTC_FLAGS[@]}" \
  -o .build/LyricsOverlay Sources/LyricsOverlay/*.swift
echo "Built .build/LyricsOverlay"
