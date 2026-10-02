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
  rm -f "$OUT_FILE" /tmp/d2_capture.xwd /tmp/d2_capture.png
}
trap cleanup EXIT

export DISPLAY=:0

timeout 10 "$BIN" > "$OUT_FILE" 2>&1 &
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

seen=0
for _ in $(seq 1 100); do
  if ! kill -0 "$BIN_PID" 2>/dev/null; then
    echo "Process died before frame=0 appeared. Output:"; cat "$OUT_FILE"; exit 1
  fi
  if grep -qE '^frame=0$' "$OUT_FILE" 2>/dev/null; then
    seen=1; break
  fi
  sleep 0.05
done
if [ "$seen" -ne 1 ]; then
  echo "Never saw 'frame=0'. Output so far:"; cat "$OUT_FILE"; exit 1
fi

sleep 0.3
xwd -id "$WIN_ID" -out /tmp/d2_capture.xwd 2>/tmp/d2_xwd_err.txt
if [ $? -ne 0 ]; then echo "xwd failed:"; cat /tmp/d2_xwd_err.txt; exit 1; fi
convert /tmp/d2_capture.xwd /tmp/d2_capture.png 2>/tmp/d2_convert_err.txt
if [ $? -ne 0 ]; then echo "convert failed:"; cat /tmp/d2_convert_err.txt; exit 1; fi

python3 "$DIR/verify.py" /tmp/d2_capture.png
VERIFY_RC=$?
if [ "$VERIFY_RC" -ne 0 ]; then exit 1; fi

wait "$BIN_PID"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Program exited with code $RC (expected 0). Output:"; cat "$OUT_FILE"
  exit 1
fi

echo "OK: raycast render matched reference silhouette, process exited 0."
exit 0
