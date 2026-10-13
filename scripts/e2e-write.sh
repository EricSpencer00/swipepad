#!/bin/sh
# End-to-end write test: writes real words into a real text field through Swipepad's insertion code.
#
# Usage: ./scripts/e2e-write.sh [textedit|web|claude] [words...]
#   textedit  a blank TextEdit document (accessibility route)
#   web       the test page in your browser, single-line field (keystroke route if it is a web editor)
#   claude    Claude's composer (keystroke route)
#
# Each case gives you a few seconds to click into the field. Then it writes each word and reports
# verified, unverified or failed. Field text is never printed.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh >/dev/null
APP="$PWD/dist/Swipepad.app"
TARGET=${1:-textedit}
[ $# -gt 0 ] && shift
WORDS=${*:-hello world}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/swipepad-e2e.XXXXXX")

case "$TARGET" in
  textedit)
    osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document with properties {text:""}' >/dev/null
    ;;
  web)
    open "$PWD/scripts/test-field.html"
    ;;
  claude)
    osascript -e 'tell application id "com.anthropic.claudefordesktop" to activate'
    ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac

COUNTDOWN=${E2E_COUNTDOWN:-6}
echo "Click into the $TARGET text field now. Starting in $COUNTDOWN seconds."
sleep "$COUNTDOWN"
focus_target() {
  case "$TARGET" in
    textedit) osascript -e 'tell application "TextEdit" to activate' ;;
    claude) osascript -e 'tell application id "com.anthropic.claudefordesktop" to activate' ;;
    web) osascript -e 'tell application "Brave Browser" to activate' 2>/dev/null || true ;;
  esac
  sleep 0.5
}
pass=0; fail=0
for word in $WORDS; do
  # Launch through Launch Services so the app itself, not Terminal, is checked for Accessibility.
  focus_target
  rm -f "$OUT/result.json" "$OUT/err.txt"
  open -g -W -n --stdout "$OUT/result.json" --stderr "$OUT/err.txt" "$APP" --args --self-test-write "$word" --delay 1 || true
  line=$(cat "$OUT/result.json" 2>/dev/null || echo '{"ok":false,"step":"launch","detail":"no result"}')
  printf '%s\n' "$line"
  case "$line" in *'"ok":true'*) pass=$((pass+1)) ;; *) fail=$((fail+1)) ;; esac
  sleep 1
done
echo "e2e $TARGET: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
