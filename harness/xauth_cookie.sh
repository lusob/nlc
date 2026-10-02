#!/usr/bin/env bash
# Prints the current X11 MIT-MAGIC-COOKIE-1 for $DISPLAY as 16 space-separated
# hex bytes (e.g. "d1 86 89 ..."). Used to fill @@XAUTH_COOKIE@@ in spec.md.
hex="$(xauth list "${DISPLAY:-:0}" 2>/dev/null | awk '$2=="MIT-MAGIC-COOKIE-1"{print $3; exit}')"
[ ${#hex} -eq 32 ] || { echo "xauth_cookie.sh: no MIT-MAGIC-COOKIE-1 found for DISPLAY=${DISPLAY:-:0}" >&2; exit 1; }
echo "$hex" | sed 's/../& /g; s/ $//'
