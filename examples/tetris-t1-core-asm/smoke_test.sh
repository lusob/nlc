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
  rm -f "$OUT_FILE" /tmp/tet_capture_*.xwd /tmp/tet_capture_*.png
}
trap cleanup EXIT

export DISPLAY=:0

timeout 30 "$BIN" > "$OUT_FILE" 2>&1 &
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
xdotool windowactivate --sync "$WIN_DEC" >/dev/null 2>&1
xdotool windowfocus "$WIN_DEC" >/dev/null 2>&1

wait_for_frame() {
  local n="$1"
  for _ in $(seq 1 600); do
    if ! kill -0 "$BIN_PID" 2>/dev/null; then return 1; fi
    grep -qE "^frame=${n}\$" "$OUT_FILE" 2>/dev/null && return 0
    sleep 0.01
  done
  return 1
}

capture_and_check() {
  local n="$1"
  xwd -id "$WIN_ID" -out "/tmp/tet_capture_${n}.xwd" 2>/tmp/tet_xwd_err.txt || { echo "xwd failed:"; cat /tmp/tet_xwd_err.txt; return 1; }
  convert "/tmp/tet_capture_${n}.xwd" "/tmp/tet_capture_${n}.png" 2>/tmp/tet_convert_err.txt || { echo "convert failed:"; cat /tmp/tet_convert_err.txt; return 1; }
  python3 "$DIR/verify.py" "/tmp/tet_capture_${n}.png" "$n"
  return $?
}

# t=1: baseline, no input yet
if ! wait_for_frame 1; then echo "died before frame=1"; cat "$OUT_FILE"; exit 1; fi
if ! capture_and_check 1; then exit 1; fi

# send 'right' so it lands during frame 5's poll
if ! wait_for_frame 4; then echo "died before frame=4"; cat "$OUT_FILE"; exit 1; fi
xdotool key --window "$WIN_DEC" d >/dev/null 2>&1
if ! wait_for_frame 8; then echo "died before frame=8"; cat "$OUT_FILE"; exit 1; fi
if ! capture_and_check 8; then exit 1; fi

# send 'rotate' so it lands during frame 12's poll
if ! wait_for_frame 11; then echo "died before frame=11"; cat "$OUT_FILE"; exit 1; fi
xdotool key --window "$WIN_DEC" w >/dev/null 2>&1
if ! wait_for_frame 15; then echo "died before frame=15"; cat "$OUT_FILE"; exit 1; fi
if ! capture_and_check 15; then exit 1; fi

# no more input — let physics run to a deterministic later frame (lock + respawn should have happened)
if ! wait_for_frame 149; then echo "died before frame=149"; cat "$OUT_FILE"; exit 1; fi
if ! capture_and_check 149; then exit 1; fi

kill "$BIN_PID" 2>/dev/null
wait "$BIN_PID" 2>/dev/null
RC=$?

echo "OK: tetris matched reference exactly at t=1 (spawn), t=8 (after move right), t=15 (after rotate), t=149 (after lock+clear+respawn)."
exit 0
