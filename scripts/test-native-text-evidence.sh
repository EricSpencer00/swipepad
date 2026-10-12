#!/bin/sh
# Self-owned offscreen Cocoa controls; no ordered window, external app or input posting.
set -eu
cd "$(dirname "$0")/.."
fixture_output=$(mktemp -d /tmp/swipepad-native-text.XXXXXX)
fixture_cache=${TMPDIR:-/tmp}/swipepad-native-text-modules
CLANG_MODULE_CACHE_PATH="$fixture_cache" swift build -c release --disable-sandbox -j 1
fixture_bin=$(swift build -c release --disable-sandbox --show-bin-path)
fixture_sdk=$(xcrun --show-sdk-path)
swiftc -module-cache-path "$fixture_cache" -swift-version 6 -default-isolation MainActor \
  -I "$fixture_bin/Modules" -I "$fixture_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  Tests/NativeTextEvidence/main.swift "$fixture_bin"/SwipepadCore.build/*.o "$fixture_bin"/TrackpadBridge.build/*.o \
  -Xlinker "$fixture_sdk/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport.tbd" -o "$fixture_output/checks"
"$fixture_output/checks"
