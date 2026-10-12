#!/bin/sh
# Records the frontmost window for N seconds and writes an optimized GIF.
# Usage: ./scripts/record-demo.sh [seconds] [output.gif]
set -eu
SECONDS_TO_RECORD=${1:-40}
OUT=${2:-docs/demo.gif}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/swipepad-demo.XXXXXX")
GEOMETRY=$(osascript <<'APPLESCRIPT'
tell application "System Events"
  set p to first process whose frontmost is true
  tell p
    set {x, y} to position of front window
    set {w, h} to size of front window
  end tell
  return (x as text) & "," & (y as text) & "," & (w as text) & "," & (h as text)
end tell
APPLESCRIPT
)
echo "Recording window at $GEOMETRY for ${SECONDS_TO_RECORD}s. Perform the gestures now."
timeout -s INT "$SECONDS_TO_RECORD" screencapture -v -R"$GEOMETRY" "$WORK/take.mov" || true
ffmpeg -v error -y -i "$WORK/take.mov" -vf "fps=12,scale=720:-1:flags=lanczos,palettegen" "$WORK/palette.png"
ffmpeg -v error -y -i "$WORK/take.mov" -i "$WORK/palette.png" \
  -lavfi "fps=12,scale=720:-1:flags=lanczos [x]; [x][1:v] paletteuse" "$OUT"
echo "Wrote $OUT (raw take kept in $WORK until you delete it)."
