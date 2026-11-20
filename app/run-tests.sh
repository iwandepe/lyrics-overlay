#!/usr/bin/env bash
# Compiles the non-UI logic with tests/main.swift and runs it.
set -euo pipefail
cd "$(dirname "$0")"
source ./_env.sh
S=Sources/LyricsOverlay
swiftc -target "$(uname -m)-apple-macosx13.0" "${SWIFTC_FLAGS[@]}" -o .build/tests \
  $S/{LRC,TitleCleaner,PlaybackClock,SyncStore,Controller,LyricsService,BridgeServer,SampleLyrics,Version,Config,UpdateCore,ExtensionFile}.swift \
  tests/main.swift
.build/tests
