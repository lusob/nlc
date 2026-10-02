MILESTONE 2 of an X11 demoscene demo, for Linux AArch64, raw syscalls
only (no libc). GAS assembly, entry `_start`, assembled with `as`,
linked with `ld` — no compiler. Builds on milestone 1 (connect +
handshake): this milestone additionally creates a window, maps it, and
fills it with a solid color.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

## Connect + handshake (same as milestone 1)

Create AF_UNIX(1) SOCK_STREAM(1) socket, connect to
`/tmp/.X11-unix/X0` (sockaddr_un: 2-byte family=1, then the 17 ASCII
bytes `/tmp/.X11-unix/X0`, then NUL, then zero-pad to 108-byte
sun_path; total struct 110 bytes, addrlen=110).

Send the 48-byte connection setup request (identical to milestone 1):
```
offset 0:  byte 'l' (0x6c)
offset 1:  byte 0
offset 2:  u16 LE 11        (major version)
offset 4:  u16 LE 0         (minor version)
offset 6:  u16 LE 18        (auth-name length)
offset 8:  u16 LE 16        (auth-data length)
offset 10: u16 LE 0         (unused — don't skip this field)
offset 12: "MIT-MAGIC-COOKIE-1"  (18 bytes + 2 bytes zero pad = 20)
offset 32: cookie bytes: @@XAUTH_COOKIE@@
```

Read the 8-byte reply header, then `addl_len*4` more bytes into the
same buffer (loop on `read` until you have it all; addl_len is the u16
LE at offset 6). Verify offset 0 (success byte) == 1, else print
`AUTH FAILED\n` and exit_group(1).

## Parse handshake fields you need (absolute offsets in the combined buffer)

```
offset 12: u32 LE  resource_id_base
offset 24: u16 LE  vendor_len (v)
offset 29: u8      num_formats
```
```
vendor_end  = 40 + ((vendor_len + 3) & ~3)
root_offset = vendor_end + num_formats * 8
root_window_id = u32 LE at buffer[root_offset .. root_offset+4)
root_visual_id = u32 LE at buffer[root_offset+32 .. root_offset+36)
root_depth     = u8  at  buffer[root_offset+38]
```

## Allocate resource IDs

```
window_id = resource_id_base | 1
gc_id     = resource_id_base | 2
```

Print to stdout immediately: `window_id=0xXXXXXXXX\n` (8 lowercase hex
digits, same manual hex-conversion approach as milestone 1).

## CreateWindow (opcode 1) — 32-byte fixed request, no optional values

```
offset 0: u8  opcode = 1
offset 1: u8  depth = root_depth (the value you parsed, e.g. 24 — use the REAL parsed value, not a hardcoded guess)
offset 2: u16 LE request-length = 8   (in 4-byte units; 32 bytes total / 4 = 8)
offset 4: u32 LE window_id
offset 8: u32 LE parent = root_window_id
offset 12: i16 LE x = 0
offset 14: i16 LE y = 0
offset 16: u16 LE width = 300
offset 18: u16 LE height = 300
offset 20: u16 LE border-width = 0
offset 22: u16 LE class = 1              (InputOutput — NOT 0/CopyFromParent, use 1 explicitly)
offset 24: u32 LE visual = root_visual_id (use the REAL parsed value, NOT 0/CopyFromParent)
offset 28: u32 LE value-mask = 0          (no optional attributes)
```
Write these 32 bytes to the socket.

## MapWindow (opcode 8) — 8 bytes

```
offset 0: u8  opcode = 8
offset 1: u8  unused = 0
offset 2: u16 LE length = 2
offset 4: u32 LE window_id
```

## CRITICAL: sleep before drawing

After sending MapWindow, you MUST sleep for at least 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) BEFORE creating the GC or drawing
anything. Reason: when a window becomes viewable for the first time,
the X server clears it to its background — if you draw before that
settles, your drawing gets wiped out and the window ends up black.
Sleeping first avoids this race.

## CreateGC (opcode 55) — 20 bytes, sets only the foreground color

```
offset 0: u8  opcode = 55
offset 1: u8  unused = 0
offset 2: u16 LE length = 5
offset 4: u32 LE cid = gc_id
offset 8: u32 LE drawable = window_id
offset 12: u32 LE value-mask = 0x00000004   (bit 2 = GCForeground, only this bit set)
offset 16: u32 LE value = 0x0000FF00        (the foreground color — pure green, format is 0x00RRGGBB)
```

## PolyFillRectangle (opcode 70) — 20 bytes, one rectangle covering the whole window

```
offset 0: u8  opcode = 70
offset 1: u8  unused = 0
offset 2: u16 LE length = 5
offset 4: u32 LE drawable = window_id
offset 8: u32 LE gc = gc_id
offset 12: i16 LE rect.x = 0
offset 14: i16 LE rect.y = 0
offset 16: u16 LE rect.width = 300
offset 18: u16 LE rect.height = 300
```

## Finish

After sending PolyFillRectangle, sleep for 4 more seconds (nanosleep,
tv_sec=4, tv_nsec=0) — this keeps the connection (and therefore the
window) alive long enough for an external tool to screenshot it (if
the process exits, the X server destroys all its windows). Then
exit_group(0).

Summary of stdout output required: exactly one line
`window_id=0xXXXXXXXX\n` (printed right after computing window_id, as
described above) — nothing else needs to be printed.
