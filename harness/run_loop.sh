#!/usr/bin/env bash
# NLC loop harness — "loop engineering" prototype (Boris Cherny / Karpathy Loop pattern).
# Instead of a human prompting Claude turn by turn, this script IS the loop:
# it prompts Claude, compiles the result, feeds real compiler/runtime errors
# back, and repeats until a hard verification signal passes (compiles + smoke
# test) or MAX_ITERS is hit.
#
# Usage: run_loop.sh <example-dir> [max_iters] [model]
#   <example-dir> must contain: spec.md, smoke_test.sh (executable, takes the
#   built binary path as $1, exits 0 on success)

set -uo pipefail

EXAMPLE_DIR="$1"
MAX_ITERS="${2:-5}"
MODEL="${3:-fable}"

SPEC_FILE="$EXAMPLE_DIR/spec.md"
SMOKE_TEST="$EXAMPLE_DIR/smoke_test.sh"
LOG_FILE="$EXAMPLE_DIR/run.log"
SRC_FILE="$EXAMPLE_DIR/main.c"
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

log "=== NLC loop start: $EXAMPLE_DIR (model=$MODEL, max_iters=$MAX_ITERS) ==="

for i in $(seq 1 "$MAX_ITERS"); do
  log ""
  log "--- Iteration $i ---"

  if [ -z "$FEEDBACK" ]; then
    PROMPT="You are a C code generator. Write a single-file C program (C11, POSIX, no external libraries beyond libc) that satisfies this specification:

$SPEC

Output ONLY the raw C source code, no markdown fences, no explanation, no comments about what you're doing. Just the code, starting with #include lines."
  else
    PROMPT="Your previous C program failed. Here is the original spec:

$SPEC

Here is the program you wrote:
\`\`\`c
$(cat "$SRC_FILE")
\`\`\`

Here is the compiler/runtime error:
\`\`\`
$FEEDBACK
\`\`\`

Fix the program. Output ONLY the corrected, complete raw C source code, no markdown fences, no explanation."
  fi

  RAW_OUT="$(claude -p "$PROMPT" --model "$MODEL" --output-format text 2>>"$LOG_FILE")"

  # Strip markdown fences if the model added them anyway.
  echo "$RAW_OUT" | sed -e '/^```/d' > "$SRC_FILE"

  if [ ! -s "$SRC_FILE" ]; then
    log "Empty generation, aborting."
    break
  fi

  log "Generated $(wc -l < "$SRC_FILE") lines -> $SRC_FILE"

  COMPILE_ERR="$(gcc -O0 -g -Wall "$SRC_FILE" -o "$BIN_FILE" 2>&1)"
  if [ $? -ne 0 ]; then
    log "COMPILE FAILED:"
    log "$COMPILE_ERR"
    FEEDBACK="COMPILE ERROR:
$COMPILE_ERR"
    continue
  fi
  log "Compile OK."

  SMOKE_ERR="$("$SMOKE_TEST" "$BIN_FILE" 2>&1)"
  SMOKE_RC=$?
  if [ "$SMOKE_RC" -ne 0 ]; then
    log "SMOKE TEST FAILED (rc=$SMOKE_RC):"
    log "$SMOKE_ERR"
    FEEDBACK="Program compiled but failed the runtime smoke test:
$SMOKE_ERR"
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
