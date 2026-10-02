#!/usr/bin/env bash
set -uo pipefail
BIN="$1"
DIR="$(dirname "$0")"
OUT_FILE="$(mktemp)"

cleanup() {
  if [ -n "${BIN_PID:-}" ] && kill -0 "$BIN_PID" 2>/dev/null; then
    kill "$BIN_PID" 2>/dev/null
    wait "$BIN_PID" 2>/dev/null
  fi
  rm -f "$OUT_FILE" /tmp/d3_capture_*.xwd /tmp/d3_capture_*.png
}
trap cleanup EXIT

export DISPLAY=:0

timeout 25 "$BIN" > "$OUT_FILE" 2>&1 &
BIN_PID=$!

WIN_ID=""
for _ in $(seq 1 30); do
  if ! kill -0 "$BIN_PID" 2>/dev/null; then
    echo "Process exited early (before window_id). Output:"; cat "$OUT_FILE"; exit 1
  fi
  WIN_ID="$(grep -oE 'window_id=0x[0-9a-f]{8}' "$OUT_FILE" | head -1 | sed 's/window_id=//')"
  [ -n "$WIN_ID" ] && break
  sleep 0.1
done
if [ -z "$WIN_ID" ]; then
  echo "Never saw window_id. Output:"; cat "$OUT_FILE"; exit 1
fi
WIN_DEC=$((WIN_ID))

wait_for_frame() {
  local n="$1"
  for _ in $(seq 1 400); do
    if ! kill -0 "$BIN_PID" 2>/dev/null; then return 1; fi
    grep -qE "^frame=${n}\$" "$OUT_FILE" 2>/dev/null && return 0
    sleep 0.01
  done
  return 1
}

# --- baseline capture (before any input) ---
if ! wait_for_frame 1; then echo "Process died before frame=1. Output:"; cat "$OUT_FILE"; exit 1; fi
xwd -id "$WIN_ID" -out /tmp/d3_capture_base.xwd 2>/tmp/d3_xwd_err.txt || { echo "xwd failed:"; cat /tmp/d3_xwd_err.txt; exit 1; }
convert /tmp/d3_capture_base.xwd /tmp/d3_capture_base.png 2>/tmp/d3_convert_err.txt || { echo "convert failed:"; cat /tmp/d3_convert_err.txt; exit 1; }
python3 "$DIR/verify.py" baseline /tmp/d3_capture_base.png || exit 1

# --- send held 'd' (turn right) for 1.5 real seconds ---
xdotool windowactivate --sync "$WIN_DEC" >/dev/null 2>&1
xdotool windowfocus "$WIN_DEC" >/dev/null 2>&1
sleep 0.1
xdotool keydown --window "$WIN_DEC" d >/dev/null 2>&1
sleep 1.5
xdotool keyup --window "$WIN_DEC" d >/dev/null 2>&1

# --- capture well after the key was released, to confirm the turn stuck ---
if ! wait_for_frame 100; then echo "Process died before frame=100. Output:"; cat "$OUT_FILE"; exit 1; fi
xwd -id "$WIN_ID" -out /tmp/d3_capture_rot.xwd 2>/tmp/d3_xwd_err2.txt || { echo "xwd failed:"; cat /tmp/d3_xwd_err2.txt; exit 1; }
convert /tmp/d3_capture_rot.xwd /tmp/d3_capture_rot.png 2>/tmp/d3_convert_err2.txt || { echo "convert failed:"; cat /tmp/d3_convert_err2.txt; exit 1; }
python3 "$DIR/verify.py" rotated /tmp/d3_capture_rot.png || exit 1

if ! grep -qE '^press 40$' "$OUT_FILE"; then
  echo "Never saw 'press 40' (d keycode) in output. Output:"; cat "$OUT_FILE"
  exit 1
fi

wait "$BIN_PID"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Program exited with code $RC (expected 0). Output tail:"; tail -30 "$OUT_FILE"
  exit 1
fi

echo "OK: baseline matched angle=0 reference, 'd' key received and caused a visible turn, process exited 0."
exit 0
