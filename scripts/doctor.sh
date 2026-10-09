#!/bin/sh
# Read-only by default. Repairs require an explicitly selected option.
set -eu
cd "$(dirname "$0")/.."
APP=${SWIPEPAD_APP:-"$PWD/dist/Swipepad.app"}
MODE=${1:---json}
fail() {
  printf '{"schemaVersion":1,"state":"Setup needed","checks":[{"id":"launcher","status":"fail","message":"%s","repair":"%s"}]}\n' "$1" "$2"
  exit 2
}
[ -x "$APP/Contents/MacOS/Swipepad" ] || fail 'App executable is missing.' 'Run scripts/build-app.sh, then run doctor again.'
[ -d /System/Library/PrivateFrameworks/MultitouchSupport.framework ] || fail 'Private MultitouchSupport framework is missing.' 'Use a supported macOS build; no security or pointer fallback repair is attempted.'
codesign --verify --strict "$APP" 2>/dev/null || fail 'App bundle signature does not validate.' 'Rebuild the complete bundle at its stable path. Do not reset permissions or bypass Gatekeeper.'
case "$MODE" in
  --json) exec "$APP/Contents/MacOS/Swipepad" --doctor --json ;;
  --text) exec "$APP/Contents/MacOS/Swipepad" --doctor ;;
  --setup) "$APP/Contents/MacOS/Swipepad" --show-setup; open -a "$APP" --args --setup ;;
  --relaunch) exec "$APP/Contents/MacOS/Swipepad" --relaunch-owned ;;
  *) printf 'Usage: %s [--json|--text|--setup|--relaunch]\n' "$0" >&2; exit 2 ;;
esac
