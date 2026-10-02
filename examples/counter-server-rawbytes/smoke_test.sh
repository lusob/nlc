#!/usr/bin/env bash
# $1 = path to the built binary. Exit 0 = pass, non-zero = fail.
set -uo pipefail
BIN="$1"
PORT=8126
OUT_FILE="$(mktemp)"

cleanup() {
  if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -f "$OUT_FILE"
}
trap cleanup EXIT

"$BIN" > "$OUT_FILE" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Server process exited early. Output:"
    cat "$OUT_FILE"
    exit 1
  fi
  if grep -q "Listening on port $PORT" "$OUT_FILE" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! grep -q "Listening on port $PORT" "$OUT_FILE" 2>/dev/null; then
  echo "Server never printed 'Listening on port $PORT' within 3s. Output so far:"
  cat "$OUT_FILE"
  exit 1
fi

# Cross the single-digit -> double-digit boundary (1..12) and check every count is exact and sequential.
for expected in $(seq 1 12); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Server died after request $((expected - 1)). Output so far:"
    cat "$OUT_FILE"
    exit 1
  fi
  RESPONSE="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/")"
  CURL_RC=$?
  if [ "$CURL_RC" -ne 0 ]; then
    echo "curl failed with rc=$CURL_RC on request $expected. Server output so far:"
    cat "$OUT_FILE"
    exit 1
  fi
  EXPECTED_BODY="Request count: $expected"
  if [ "$RESPONSE" != "$EXPECTED_BODY" ]; then
    echo "Request $expected: got '$RESPONSE', expected '$EXPECTED_BODY'"
    exit 1
  fi
done

exit 0
