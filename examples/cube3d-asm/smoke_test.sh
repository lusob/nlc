#!/usr/bin/env bash
set -uo pipefail
BIN="$1"
DIR="$(dirname "$0")"
OUT_FILE="$(mktemp)"

timeout 10 "$BIN" > "$OUT_FILE" 2>&1
RC=$?

if [ "$RC" -eq 124 ]; then
  echo "Binary did not exit within 10s (should self-terminate after 64 frames). Output size so far: $(wc -c < "$OUT_FILE") bytes"
  rm -f "$OUT_FILE"
  exit 1
fi

if [ "$RC" -ne 0 ]; then
  echo "Exit code was $RC, expected 0. Output size: $(wc -c < "$OUT_FILE") bytes. First 200 bytes (escaped):"
  head -c 200 "$OUT_FILE" | cat -v
  rm -f "$OUT_FILE"
  exit 1
fi

python3 "$DIR/verify.py" "$OUT_FILE"
VERIFY_RC=$?
rm -f "$OUT_FILE"
exit $VERIFY_RC
