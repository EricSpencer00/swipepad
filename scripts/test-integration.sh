#!/bin/sh
# Explicit interactive integration test. Creates only a fresh disposable document.
set -eu
cd "$(dirname "$0")/.."
swift scripts/fixture-lifecycle.swift --preflight
fixture_dir=$(mktemp -d /tmp/swipepad-integration.XXXXXX)
fixture_document="$fixture_dir/Swipepad Automated Fixture.rtf"
printf '%s\n' "$fixture_document" > "$fixture_dir/.swipepad-owned"
cleanup_fixture() {
  swift scripts/fixture-lifecycle.swift --finish "$fixture_document" "$fixture_dir/evidence" || printf '%s\n' 'Fixture retained safely: complete native Save As/close cleanup before another run.'
}
trap cleanup_fixture EXIT
# One document per run, reused by every trial. EXIT snapshots on success/failure;
# edited/ambiguous windows stay open for explicit Save As and block the next run.
printf '%s' '{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 }' > "$fixture_document"
printf 'Owned disposable document: %s\n' "$fixture_document"
swift build -c release
fixture_bin=$(swift build -c release --show-bin-path)
swiftc -swift-version 6 -default-isolation MainActor \
  -I "$fixture_bin/Modules" -I "$fixture_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  Tests/LiftIntegration/main.swift "$fixture_bin"/SwipepadCore.build/*.o "$fixture_bin"/TrackpadBridge.build/*.o \
  -F /System/Library/PrivateFrameworks -framework MultitouchSupport \
  -o "$fixture_dir/SwipepadIntegrationChecks"
"$fixture_dir/SwipepadIntegrationChecks" "$fixture_document"
