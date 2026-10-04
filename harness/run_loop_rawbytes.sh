#!/usr/bin/env bash
# NLC loop harness — variant C: LLM emits the raw ELF64 $ARCH_LABEL executable
# bytes directly (hex), with NO assembler, NO linker, NO compiler at all.
# The harness only converts hex -> binary and chmod +x's it.
#
# Usage: run_loop_rawbytes.sh <example-dir> [max_iters] [model]
#   <example-dir> must contain: spec.md, smoke_test.sh

set -uo pipefail

source "$(dirname "$0")/arch.sh" || exit 1

EXAMPLE_DIR="$1"
MAX_ITERS="${2:-8}"
MODEL="${3:-fable}"

SPEC_FILE="$(spec_path "$EXAMPLE_DIR")"
SMOKE_TEST="$EXAMPLE_DIR/smoke_test.sh"
LOG_FILE="$EXAMPLE_DIR/run.log"
HEX_FILE="$EXAMPLE_DIR/main.hex"
BIN_FILE="$EXAMPLE_DIR/app"

[ -f "$SPEC_FILE" ] || { echo "Missing $SPEC_FILE"; exit 1; }
[ -x "$SMOKE_TEST" ] || { echo "Missing/non-executable $SMOKE_TEST"; exit 1; }

: > "$LOG_FILE"
log() { echo "$1" | tee -a "$LOG_FILE"; }

SPEC="$(cat "$SPEC_FILE")"
if grep -q '@@XAUTH_COOKIE@@' "$SPEC_FILE"; then
  COOKIE="$("$(dirname "$0")/xauth_cookie.sh")" || exit 1
  SPEC="${SPEC//@@XAUTH_COOKIE@@/$COOKIE}"
fi
FEEDBACK=""
SUCCESS=0

log "=== NLC raw-bytes loop start: $EXAMPLE_DIR (arch=$ARCH, model=$MODEL, max_iters=$MAX_ITERS) ==="

BASE_RULES="$RAW_RULES"

for i in $(seq 1 "$MAX_ITERS"); do
  log ""
  log "--- Iteration $i ---"

  if [ -z "$FEEDBACK" ]; then
    PROMPT="You are a raw ELF64/$ARCH_LABEL machine code generator. Produce a minimal, valid, statically-linked ELF64 executable (as raw hex bytes) that satisfies this specification:

$SPEC

$BASE_RULES"
  else
    PROMPT="Your previous raw ELF bytes failed. Original spec:

$SPEC

$BASE_RULES

Here is the hex you produced (as read back from the file we tried to run):
\`\`\`
$(cat "$HEX_FILE" 2>/dev/null | head -c 4000)
\`\`\`

Here is what went wrong:
\`\`\`
$FEEDBACK
\`\`\`

Fix it. Output ONLY the corrected, complete hex byte stream for the whole file, nothing else."
  fi

  RAW_OUT="$(claude -p "$PROMPT" --model "$MODEL" --output-format text 2>>"$LOG_FILE")"
  if echo "$RAW_OUT" | grep -qiE "hit your (session|usage) limit|requires usage credits"; then
    log "ABORTED: model unavailable (usage limit): $RAW_OUT"
    exit 2
  fi
  # Strip everything except hex digits (drop fences, whitespace, any stray prose char that isn't 0-9a-fA-F).
  echo "$RAW_OUT" | tr -cd '0-9a-fA-F' > "$HEX_FILE"

  if [ ! -s "$HEX_FILE" ]; then
    log "Empty generation, aborting."
    break
  fi
  log "Generated $(($(wc -c < "$HEX_FILE") / 2)) bytes of hex -> $HEX_FILE"

  # Odd number of hex digits -> malformed, drop last nibble so xxd doesn't choke, but flag it as feedback.
  HEXLEN=$(wc -c < "$HEX_FILE")
  if [ $((HEXLEN % 2)) -ne 0 ]; then
    truncate -s -1 "$HEX_FILE"
    log "WARNING: odd hex digit count, truncated last nibble."
  fi

  if ! xxd -r -p "$HEX_FILE" > "$BIN_FILE" 2>"$EXAMPLE_DIR/xxd_err.txt"; then
    XXD_ERR="$(cat "$EXAMPLE_DIR/xxd_err.txt")"
    log "HEX DECODE FAILED: $XXD_ERR"
    FEEDBACK="Could not even decode the hex you emitted as bytes: $XXD_ERR"
    continue
  fi
  chmod +x "$BIN_FILE"

  READELF_ERR="$(readelf -h "$BIN_FILE" 2>&1)"
  if [ $? -ne 0 ]; then
    log "NOT A VALID ELF FILE:"
    log "$READELF_ERR"
    FEEDBACK="readelf -h could not parse this as a valid ELF file:
$READELF_ERR"
    continue
  fi
  log "readelf validates the ELF header OK."

  SMOKE_ERR="$("$SMOKE_TEST" "$BIN_FILE" 2>&1)"
  SMOKE_RC=$?
  if [ "$SMOKE_RC" -ne 0 ]; then
    log "SMOKE TEST FAILED (rc=$SMOKE_RC):"
    log "$SMOKE_ERR"
    FEEDBACK="ELF header parsed but running it failed the smoke test:
$SMOKE_ERR

Your file is $(wc -c < "$BIN_FILE") bytes. This is what readelf actually decoded from your bytes (compare against what you intended — a single extra or missing hex digit in a long run of zeros shifts every later field):
$(readelf -lh "$BIN_FILE" 2>&1 | grep -E 'Machine|Entry|Type:|LOAD|Offset|FileSiz|MemSiz|Flags' | head -20)"
    continue
  fi

  log "SMOKE TEST PASSED."
  SUCCESS=1
  break
done

log ""
if [ "$SUCCESS" -eq 1 ]; then
  log "=== RESULT: SUCCESS after $i/$MAX_ITERS iteration(s) ==="
  exit 0
else
  log "=== RESULT: FAILED after $MAX_ITERS iteration(s) ==="
  exit 1
fi
