#!/usr/bin/env bash
# NLC loop harness — variant B: LLM writes raw AArch64 assembly (Linux
# syscalls directly, no libc), assembled with `as` and linked with `ld`.
# No compiler involved — as/ld only translate/link, they don't parse or
# codegen from a high-level language.
#
# Usage: run_loop_asm.sh <example-dir> [max_iters] [model]
#   <example-dir> must contain: spec.md, smoke_test.sh

set -uo pipefail

EXAMPLE_DIR="$1"
MAX_ITERS="${2:-6}"
MODEL="${3:-fable}"

SPEC_FILE="$EXAMPLE_DIR/spec.md"
SMOKE_TEST="$EXAMPLE_DIR/smoke_test.sh"
LOG_FILE="$EXAMPLE_DIR/run.log"
SRC_FILE="$EXAMPLE_DIR/main.s"
OBJ_FILE="$EXAMPLE_DIR/app.o"
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

log "=== NLC asm loop start: $EXAMPLE_DIR (model=$MODEL, max_iters=$MAX_ITERS) ==="

BASE_RULES="Target: Linux AArch64 (ARM64), GNU assembler (GAS) syntax.
Rules:
- Raw Linux syscalls only (svc #0, syscall number in x8, args in x0-x5, return in x0). NO libc, NO C library calls, NO crt startup.
- Must define '.global _start' as the entry point (not 'main').
- Must end by calling the exit_group syscall (number 94) directly — do not fall off the end.
- Relevant AArch64 Linux syscall numbers: read=63 write=64 exit=93 exit_group=94 socket=198 bind=200 listen=201 accept=202 close=57.
- socket/bind/accept struct layouts follow standard Linux sockaddr_in (AF_INET=2)."

for i in $(seq 1 "$MAX_ITERS"); do
  log ""
  log "--- Iteration $i ---"

  if [ -z "$FEEDBACK" ]; then
    PROMPT="You are an AArch64 assembly code generator. Write raw GNU assembler (AT&T is irrelevant on ARM, use standard GAS AArch64 mnemonics) that satisfies this specification:

$SPEC

$BASE_RULES

Output ONLY the raw assembly source, no markdown fences, no explanation, no comments needed (a few short comments are fine but keep it minimal)."
  else
    PROMPT="Your previous AArch64 assembly program failed. Original spec:

$SPEC

$BASE_RULES

Here is the assembly you wrote:
\`\`\`
$(cat "$SRC_FILE")
\`\`\`

Here is the assembler/linker/runtime error:
\`\`\`
$FEEDBACK
\`\`\`

Fix it. Output ONLY the corrected, complete raw assembly source, no markdown fences, no explanation."
  fi

  RAW_OUT="$(claude -p "$PROMPT" --model "$MODEL" --output-format text 2>>"$LOG_FILE")"
  echo "$RAW_OUT" | sed -e '/^```/d' > "$SRC_FILE"

  if [ ! -s "$SRC_FILE" ]; then
    log "Empty generation, aborting."
    break
  fi
  log "Generated $(wc -l < "$SRC_FILE") lines -> $SRC_FILE"

  ASM_ERR="$(as -o "$OBJ_FILE" "$SRC_FILE" 2>&1)"
  if [ $? -ne 0 ]; then
    log "ASSEMBLE FAILED:"
    log "$ASM_ERR"
    FEEDBACK="ASSEMBLER ERROR:
$ASM_ERR"
    continue
  fi

  LD_ERR="$(ld -o "$BIN_FILE" "$OBJ_FILE" 2>&1)"
  if [ $? -ne 0 ]; then
    log "LINK FAILED:"
    log "$LD_ERR"
    FEEDBACK="LINKER ERROR:
$LD_ERR"
    continue
  fi
  log "Assemble+link OK."

  SMOKE_ERR="$("$SMOKE_TEST" "$BIN_FILE" 2>&1)"
  SMOKE_RC=$?
  if [ "$SMOKE_RC" -ne 0 ]; then
    log "SMOKE TEST FAILED (rc=$SMOKE_RC):"
    log "$SMOKE_ERR"
    FEEDBACK="Program assembled and linked but failed the runtime smoke test:
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
