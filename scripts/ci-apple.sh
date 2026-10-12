#!/bin/sh
# One serial headless Apple CI run; owned GUI execution remains an explicit coordinated step.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { printf '%s\n' 'BLOCKED: Apple toolchain required'; exit 3; }
[ -z "$(git status --porcelain --untracked-files=all)" ] || { printf '%s\n' 'BLOCKED: CI requires a clean committed source'; exit 3; }
ci_head=$(git rev-parse HEAD)
ci_output=${SWIPEPAD_CI_ARTIFACTS:-$(mktemp -d /tmp/swipepad-apple-ci.XXXXXX)}
mkdir -p "$ci_output"
printf '%s\n' "$ci_head" > "$ci_output/exact-head.txt"
swift build --scratch-path "$ci_output/build" -c release --disable-sandbox -j 1 > "$ci_output/build.log" 2>&1
ci_bin=$(swift build --scratch-path "$ci_output/build" -c release --disable-sandbox --show-bin-path)
"$ci_bin/SwipepadChecks" > "$ci_output/core.log" 2>&1
ci_sdk=$(xcrun --show-sdk-path)
for ci_kind in RepeatFlow WebFieldIntegration; do
 swiftc -module-cache-path "$ci_output/modules" -swift-version 6 -default-isolation MainActor \
  -I "$ci_bin/Modules" -I "$ci_bin/TrackpadBridge.build" \
  Sources/Swipepad/App.swift Sources/Swipepad/DoctorSupport.swift Sources/Swipepad/SetupView.swift Sources/Swipepad/Overlay.swift \
  "Tests/$ci_kind/main.swift" "$ci_bin"/SwipepadCore.build/*.o "$ci_bin"/TrackpadBridge.build/*.o \
  -Xlinker "$ci_sdk/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport.tbd" -o "$ci_output/$ci_kind" > "$ci_output/$ci_kind-compile.log" 2>&1
done
"$ci_output/RepeatFlow" > "$ci_output/repeat.log" 2>&1
printf 'PASS Apple build/core/port-handler checks at %s\n' "$ci_head"
tail -n 1 "$ci_output/core.log"
tail -n 1 "$ci_output/repeat.log"
printf 'Owned web fixture compiled, not run. GUI/physical acceptance requires coordinated execution.\nArtifacts: %s\n' "$ci_output"
