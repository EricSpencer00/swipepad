#!/bin/sh
# Production repeat handlers with memory-only input ports; no UI, input posting or permission request.
set -eu
cd "$(dirname "$0")/.."
fixture_cache=${TMPDIR:-/tmp}/swipepad-repeat-module-cache
mkdir -p "$fixture_cache"
CLANG_MODULE_CACHE_PATH="$fixture_cache" swift build -c release --disable-sandbox
fixture_bin=$(swift build -c release --disable-sandbox --show-bin-path)
fixture_dir=$(mktemp -d /tmp/swipepad-repeat.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
swiftc -module-cache-path "$fixture_cache" -swift-version 6 -default-isolation MainActor \
  -I "$fixture_bin/Modules" -I "$fixture_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  Tests/RepeatFlow/main.swift "$fixture_bin"/SwipepadCore.build/*.o "$fixture_bin"/TrackpadBridge.build/*.o \
  -F /System/Library/PrivateFrameworks -framework MultitouchSupport -o "$fixture_dir/checks"
"$fixture_dir/checks"
