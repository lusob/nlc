#!/usr/bin/env bash
# $1 = path to the built binary. Exit 0 = pass, non-zero = fail.
set -uo pipefail
BIN="$1"
PORT=8123
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

# Wait up to 3s for the "Listening" line, bail early if the process died.
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

RESPONSE="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/")"
CURL_RC=$?

if [ "$CURL_RC" -ne 0 ]; then
  echo "curl failed with rc=$CURL_RC (server output so far:)"
  cat "$OUT_FILE"
  exit 1
fi

if [ "$RESPONSE" != "Hello from NLC" ]; then
  echo "Unexpected response body: '$RESPONSE' (expected 'Hello from NLC')"
  exit 1
fi

# A second request must also work (proves it doesn't exit after one request).
RESPONSE2="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/anything")"
if [ "$RESPONSE2" != "Hello from NLC" ]; then
  echo "Second request failed or unexpected body: '$RESPONSE2'"
  exit 1
fi

exit 0
