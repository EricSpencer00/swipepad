#!/bin/sh
# Compile by default. --run is an interactive owned-window test requiring human coordination.
set -eu
cd "$(dirname "$0")/.."
case "${1:---compile}" in --compile|--run) mode=${1:---compile} ;; *) printf '%s\n' 'Usage: scripts/test-web-field.sh [--compile|--run]'; exit 2 ;; esac
fixture_cache=${TMPDIR:-/tmp}/swipepad-web-module-cache
mkdir -p "$fixture_cache"
CLANG_MODULE_CACHE_PATH="$fixture_cache" swift build -c release --disable-sandbox
fixture_bin=$(swift build -c release --disable-sandbox --show-bin-path)
fixture_dir=$(mktemp -d /tmp/swipepad-web.XXXXXX)
fixture_sdk=$(xcrun --show-sdk-path)
# Link the one SDK private stub directly; a broad private-framework search shadows Network.
swiftc -module-cache-path "$fixture_cache" -swift-version 6 -default-isolation MainActor \
  -I "$fixture_bin/Modules" -I "$fixture_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  Tests/WebFieldIntegration/main.swift "$fixture_bin"/SwipepadCore.build/*.o "$fixture_bin"/TrackpadBridge.build/*.o \
  -Xlinker "$fixture_sdk/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport.tbd" -o "$fixture_dir/checks"
printf 'Compiled owned web fixture: %s\n' "$fixture_dir/checks"
if [ "$mode" = --run ]; then "$fixture_dir/checks"; fi
