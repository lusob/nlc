#!/usr/bin/env bash
# $1 = path to the built binary. Exit 0 = pass, non-zero = fail (stdout/stderr is fed back to the loop as feedback).
set -uo pipefail
BIN="$1"

OUT="$("$BIN")"
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "Exit code was $RC, expected 0"
  exit 1
fi

if [ "$OUT" != "Hello, world!" ]; then
  echo "stdout was: '$OUT' (expected exactly 'Hello, world!')"
  exit 1
fi

exit 0
