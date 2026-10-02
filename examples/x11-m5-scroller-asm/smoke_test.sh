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
  rm -f "$OUT_FILE" /tmp/m5_capture_*.xwd /tmp/m5_capture_*.png
}
trap cleanup EXIT

export DISPLAY=:0

timeout 15 "$BIN" > "$OUT_FILE" 2>&1 &
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

capture_frame() {
  local frame_num="$1"
  local seen=0
  for _ in $(seq 1 300); do
    if ! kill -0 "$BIN_PID" 2>/dev/null; then
      echo "Process died before frame=$frame_num appeared. Output:"; cat "$OUT_FILE"; return 1
    fi
    if grep -qE "^frame=${frame_num}\$" "$OUT_FILE" 2>/dev/null; then
      seen=1; break
    fi
    sleep 0.01
  done
  if [ "$seen" -ne 1 ]; then
    echo "Never saw 'frame=$frame_num'. Output so far:"; cat "$OUT_FILE"; return 1
  fi
  xwd -id "$WIN_ID" -out "/tmp/m5_capture_${frame_num}.xwd" 2>/tmp/m5_xwd_err.txt
  if [ $? -ne 0 ]; then echo "xwd failed for frame $frame_num:"; cat /tmp/m5_xwd_err.txt; return 1; fi
  convert "/tmp/m5_capture_${frame_num}.xwd" "/tmp/m5_capture_${frame_num}.png" 2>/tmp/m5_convert_err.txt
  if [ $? -ne 0 ]; then echo "convert failed for frame $frame_num:"; cat /tmp/m5_convert_err.txt; return 1; fi
  python3 "$DIR/verify.py" "/tmp/m5_capture_${frame_num}.png" "$frame_num"
  return $?
}

if ! capture_frame 0; then exit 1; fi
if ! capture_frame 30; then exit 1; fi
if ! capture_frame 80; then exit 1; fi

wait "$BIN_PID"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Program exited with code $RC (expected 0). Output:"; cat "$OUT_FILE"
  exit 1
fi

echo "OK: scroller verified at frames 0, 30, 80 (pixel-exact match to reference), process exited 0."
exit 0
