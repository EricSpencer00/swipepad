#!/bin/sh
# Explicit interactive integration test. Creates only a fresh disposable document.
set -eu
cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d /tmp/swipepad-integration.XXXXXX)
fixture_document="$fixture_dir/Swipepad Automated Fixture.rtf"
printf '%s' '{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 }' > "$fixture_document"
printf 'Owned disposable document: %s\n' "$fixture_document"
swift build -c release
fixture_bin=$(swift build -c release --show-bin-path)
swiftc -swift-version 6 -default-isolation MainActor \
  -I "$fixture_bin/Modules" -I "$fixture_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  Tests/Integration/main.swift "$fixture_bin"/SwipepadCore.build/*.o "$fixture_bin"/TrackpadBridge.build/*.o \
  -F /System/Library/PrivateFrameworks -framework MultitouchSupport \
  -o "$fixture_dir/SwipepadIntegrationChecks"
"$fixture_dir/SwipepadIntegrationChecks" "$fixture_document"
