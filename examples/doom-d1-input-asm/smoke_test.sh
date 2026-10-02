#!/usr/bin/env bash
set -uo pipefail
BIN="$1"
OUT_FILE="$(mktemp)"

cleanup() {
  if [ -n "${BIN_PID:-}" ] && kill -0 "$BIN_PID" 2>/dev/null; then
    kill "$BIN_PID" 2>/dev/null
    wait "$BIN_PID" 2>/dev/null
  fi
  rm -f "$OUT_FILE"
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

WIN_DEC=$((WIN_ID))

sleep 0.3
xdotool windowactivate --sync "$WIN_DEC" >/dev/null 2>&1
xdotool windowfocus "$WIN_DEC" >/dev/null 2>&1
sleep 0.2

# Send a known sequence: w, a, s, d — each with a small gap.
for key in w a s d; do
  xdotool key --window "$WIN_DEC" "$key" >/dev/null 2>&1
  sleep 0.3
done

wait "$BIN_PID"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Program exited with code $RC (expected 0). Output:"; cat "$OUT_FILE"
  exit 1
fi

# Expected keycodes in order: w=25, a=38, s=39, d=40, each a press then a release.
EXPECTED="press 25
release 25
press 38
release 38
press 39
release 39
press 40
release 40"

ACTUAL="$(grep -E '^(press|release) [0-9]+$' "$OUT_FILE")"

if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Key event sequence mismatch."
  echo "--- expected ---"
  echo "$EXPECTED"
  echo "--- actual ---"
  echo "$ACTUAL"
  echo "--- full output ---"
  cat "$OUT_FILE"
  exit 1
fi

echo "OK: received exact expected press/release sequence for w,a,s,d (keycodes 25,38,39,40)."
exit 0
