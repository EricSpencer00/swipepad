#!/bin/sh
# Sets up a clean test session: builds and launches Swipepad, opens the test field page
# and a blank TextEdit document. Nothing personal is opened or recorded.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh >/dev/null
open dist/Swipepad.app
open scripts/test-field.html
osascript <<'APPLESCRIPT'
tell application "TextEdit"
  activate
  make new document with properties {text:""}
end tell
APPLESCRIPT
cat <<'STEPS'

Ready. Before recording:
  1. Allow Swipepad under System Settings > Privacy & Security > Accessibility.
  2. Allow your terminal under Screen Recording, so screencapture can record.
  3. Close Messages and other apps with private content. Only the test window is recorded.

Then run ./scripts/record-demo.sh 40 and, while it records:
  - click into the blank TextEdit window and double-tap Command
  - swipe "hello" with one finger across the keys, then lift
  - swipe "world", then lift
  - press Escape to turn swiping off
STEPS
