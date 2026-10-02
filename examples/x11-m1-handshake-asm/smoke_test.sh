#!/usr/bin/env bash
set -uo pipefail
BIN="$1"

OUT="$(timeout 5 "$BIN" 2>&1)"
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "Exit code was $RC, expected 0. Output:"
  echo "$OUT"
  exit 1
fi

GOT_WINDOW="$(echo "$OUT" | grep -oE 'root_window=0x[0-9a-f]{8}' | head -1)"
GOT_VISUAL="$(echo "$OUT" | grep -oE 'root_visual=0x[0-9a-f]{8}' | head -1)"

if [ -z "$GOT_WINDOW" ] || [ -z "$GOT_VISUAL" ]; then
  echo "Could not find 'root_window=0x........' and/or 'root_visual=0x........' in output:"
  echo "$OUT"
  exit 1
fi

# Independent ground truth via a completely different tool (xdpyinfo), queried fresh each time.
REF="$(DISPLAY=:0 xdpyinfo)"
REF_WINDOW="0x$(echo "$REF" | grep -oE 'root window id:\s+0x[0-9a-f]+' | grep -oE '0x[0-9a-f]+' | sed 's/^0x//' | awk '{printf "%08s", $0}' | tr ' ' 0)"
REF_VISUAL="0x$(echo "$REF" | grep -oE 'default visual id:\s+0x[0-9a-f]+' | grep -oE '0x[0-9a-f]+' | sed 's/^0x//' | awk '{printf "%08s", $0}' | tr ' ' 0)"

GOT_WINDOW_VAL="${GOT_WINDOW#root_window=}"
GOT_VISUAL_VAL="${GOT_VISUAL#root_visual=}"

# Normalize both sides by stripping leading zeros for numeric comparison (avoid hex-width mismatches).
norm() { printf "%d" "$1" 2>/dev/null; }

if [ "$(norm "$GOT_WINDOW_VAL")" != "$(norm "$REF_WINDOW")" ]; then
  echo "root_window mismatch: program said $GOT_WINDOW_VAL, xdpyinfo says $REF_WINDOW"
  exit 1
fi

if [ "$(norm "$GOT_VISUAL_VAL")" != "$(norm "$REF_VISUAL")" ]; then
  echo "root_visual mismatch: program said $GOT_VISUAL_VAL, xdpyinfo says $REF_VISUAL"
  exit 1
fi

echo "OK: root_window=$GOT_WINDOW_VAL root_visual=$GOT_VISUAL_VAL match xdpyinfo exactly."
exit 0
