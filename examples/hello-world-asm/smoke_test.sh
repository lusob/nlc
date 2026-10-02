#!/usr/bin/env bash
set -uo pipefail
BIN="$1"
OUT="$("$BIN")"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "Exit code was $RC, expected 0"
  exit 1
fi
if [ "$OUT" != "Hello, world!" ]; then
  echo "stdout was: '$OUT' (expected exactly 'Hello, world!' before the trailing newline)"
  exit 1
fi
exit 0
