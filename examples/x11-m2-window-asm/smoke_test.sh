#!/usr/bin/env bash
set -uo pipefail
BIN="$1"
OUT_FILE="$(mktemp)"
XWD_FILE="$(mktemp --suffix=.xwd)"
PNG_FILE="$(mktemp --suffix=.png)"

cleanup() {
  if [ -n "${BIN_PID:-}" ] && kill -0 "$BIN_PID" 2>/dev/null; then
    kill "$BIN_PID" 2>/dev/null
    wait "$BIN_PID" 2>/dev/null
  fi
  rm -f "$OUT_FILE" "$XWD_FILE" "$PNG_FILE"
}
trap cleanup EXIT

export DISPLAY=:0

timeout 8 "$BIN" > "$OUT_FILE" 2>&1 &
BIN_PID=$!

# Wait up to 3s for the window_id line.
WIN_ID=""
for _ in $(seq 1 30); do
  if ! kill -0 "$BIN_PID" 2>/dev/null; then
    echo "Process exited early (before printing window_id). Output:"
    cat "$OUT_FILE"
    exit 1
  fi
  WIN_ID="$(grep -oE 'window_id=0x[0-9a-f]{8}' "$OUT_FILE" | head -1 | sed 's/window_id=//')"
  if [ -n "$WIN_ID" ]; then
    break
  fi
  sleep 0.1
done

if [ -z "$WIN_ID" ]; then
  echo "Never saw 'window_id=0x........' in output within 3s. Output so far:"
  cat "$OUT_FILE"
  exit 1
fi

# Give it time to: sleep 300ms (per spec) + create GC + fill + settle. Be generous.
sleep 1.5

if ! kill -0 "$BIN_PID" 2>/dev/null; then
  echo "Process exited before we could screenshot it. Output:"
  cat "$OUT_FILE"
  exit 1
fi

if ! xwd -id "$WIN_ID" -out "$XWD_FILE" 2>/tmp/xwd_err.txt; then
  echo "xwd failed to capture window $WIN_ID:"
  cat /tmp/xwd_err.txt
  exit 1
fi

if ! convert "$XWD_FILE" "$PNG_FILE" 2>/tmp/convert_err.txt; then
  echo "convert failed:"
  cat /tmp/convert_err.txt
  exit 1
fi

W="$(identify -format '%w' "$PNG_FILE" 2>/dev/null)"
H="$(identify -format '%h' "$PNG_FILE" 2>/dev/null)"
# Allow a little slack (xwd/decorations can add a 1px border) instead of requiring an exact 300x300.
if [ "$W" -lt 299 ] || [ "$W" -gt 305 ] || [ "$H" -lt 299 ] || [ "$H" -gt 305 ]; then
  echo "Window dimensions were ${W}x${H}, expected ~300x300"
  exit 1
fi

# Check several sample points well inside the window, not just the center, to catch a partial fill.
for coord in "150,150" "15,15" "280,280" "15,280" "280,15"; do
  PIXEL="$(convert "$PNG_FILE" -format "%[pixel:p{$coord}]" info: 2>/dev/null)"
  if [ "$PIXEL" != "srgb(0,255,0)" ] && [ "$PIXEL" != "rgb(0,255,0)" ] && [ "$PIXEL" != "green" ]; then
    echo "Pixel at ($coord) was '$PIXEL', expected pure green (srgb(0,255,0))."
    exit 1
  fi
done

# Let the program finish its own 4s sleep and exit cleanly.
wait "$BIN_PID"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Program exited with code $RC (expected 0) after the screenshot check. Output:"
  cat "$OUT_FILE"
  exit 1
fi

echo "OK: window $WIN_ID is 300x300, fully green (5 sample points checked), process exited 0."
exit 0
