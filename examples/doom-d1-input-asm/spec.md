MILESTONE D1 of a Doom-style raycaster project, Linux AArch64, raw
syscalls only (no libc). GAS assembly, entry `_start`, `as`+`ld`, no
compiler. This milestone is ONLY about keyboard input over X11 — no
rendering, no map, no player movement yet. Prove that raw asm can
receive and correctly parse real X11 KeyPress/KeyRelease events.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94, fcntl=25.

## Connect + handshake (identical to previous X11 milestones, repeat verbatim)

AF_UNIX(1) SOCK_STREAM(1) socket, connect `/tmp/.X11-unix/X0`
(sockaddr_un: family=1 u16, 17 bytes `/tmp/.X11-unix/X0`, NUL, pad to
108-byte sun_path, struct=110 bytes, addrlen=110).

48-byte setup request:
```
offset 0: 'l'(0x6c)  offset 1: 0  offset 2: u16 LE 11  offset 4: u16 LE 0
offset 6: u16 LE 18  offset 8: u16 LE 16  offset 10: u16 LE 0
offset 12: "MIT-MAGIC-COOKIE-1" (18 bytes + 2 zero pad)
offset 32: cookie: @@XAUTH_COOKIE@@
```
Read 8-byte header, then `addl_len*4` bytes (addl_len = u16 LE at
offset 6), looping on `read`. Verify success byte (offset 0) == 1.

Parse: `resource_id_base` = u32 LE at offset 12. `vendor_len` = u16 LE
at offset 24. `num_formats` = u8 at offset 29.
`root_offset = 40 + ((vendor_len+3)&~3) + num_formats*8`.
`root_window_id` = u32 LE at `buffer[root_offset..+4)`.
`root_visual_id` = u32 LE at `buffer[root_offset+32..+36)`.
`root_depth` = u8 at `buffer[root_offset+38]`.

## Resource ID

`window_id = resource_id_base | 1`. Print `window_id=0xXXXXXXXX\n` to
stdout right after computing it.

## CreateWindow (opcode 1) — THIS TIME WITH AN EVENT MASK (new — not used before)

CreateWindow requests can carry optional attributes selected by a
`value-mask` bitfield, with one 4-byte value per set bit appended
after the 32-byte fixed part, in bit order. We're setting exactly ONE
bit: bit 11 (`CWEventMask`, mask value `0x00000800`), whose value is
an event-mask selecting which events we want delivered: KeyPress
(`0x00000001`) OR'd with KeyRelease (`0x00000002`) = `0x00000003`.

```
offset 0: u8 opcode = 1
offset 1: u8 depth = root_depth
offset 2: u16 LE length = 9        (32 fixed bytes + 4 value bytes = 36 bytes = 9 units)
offset 4: u32 LE window_id
offset 8: u32 LE parent = root_window_id
offset 12: i16 LE x=0
offset 14: i16 LE y=0
offset 16: u16 LE width=200
offset 18: u16 LE height=100
offset 20: u16 LE border-width=0
offset 22: u16 LE class=1 (InputOutput)
offset 24: u32 LE visual = root_visual_id
offset 28: u32 LE value-mask = 0x00000800     (CWEventMask, only this bit set)
offset 32: u32 LE value = 0x00000003          (KeyPress | KeyRelease)
```
Total request = 36 bytes.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — same critical reason as always.

## Set the socket to non-blocking (fcntl, syscall 25)

`fcntl(fd, F_SETFL, O_NONBLOCK)`: `x0=fd` (the socket file descriptor
you got from the `socket` syscall earlier — keep it in a saved
register), `x1=4` (F_SETFL), `x2=0x800` (O_NONBLOCK), `x8=25`, `svc
#0`. After this, `read()` on the socket returns immediately even if
there's no data — check the return value: if it's negative (an errno,
specifically -EAGAIN which is -11), that means "no data right now",
NOT an error to report — just treat it as "nothing to read this time"
and move on. Any read() that returns >0 is real data.

## Event format (when read() DOES return data)

Each event is exactly 32 bytes. The first byte tells you the type
(mask off the top bit with `& 0x7f` first, the top bit just means
"this was sent via the SendEvent protocol request" which you don't
care about):
```
byte 0 (masked with 0x7f): event type — 2 = KeyPress, 3 = KeyRelease (ignore any other type, e.g. 34=MappingNotify, just skip that 32-byte chunk)
byte 1: detail — this IS the keycode (0-255)
```
You don't need any other field for this milestone. A single `read()`
call on the socket might return MULTIPLE 32-byte events back to back
(or a partial one at the very start if you're unlucky, but for this
exercise assume reads are 32-byte-aligned — process the buffer 32
bytes at a time until you run out of the bytes actually returned by
this read() call).

## Main loop (run for ~5 seconds, then exit)

Loop 200 times (t = 0 to 199):
1. In an inner loop: call `read(fd, buf, 4096)` repeatedly. Each call:
   - If it returns a negative value: no more data pending right now, break out of the inner loop.
   - If it returns a positive value N: you got N bytes (a multiple of 32). For each 32-byte chunk: check `buf[0] & 0x7f`. If it's 2: print `press ` followed by the decimal ASCII value of `buf[1]` (hand-rolled itoa, keycodes are 0-255 so up to 3 digits, no leading zeros), then `\n`. If it's 3: print `release ` followed by the same decimal keycode, then `\n`. Otherwise ignore that chunk. Then loop the inner read again (there might be more).
2. Sleep 25ms (nanosleep, tv_sec=0, tv_nsec=25000000).
3. Increment t, continue the outer loop until t=200.

After the outer loop, exit_group(0).

Expected behavior: while this program runs (~5 seconds), any real
keypresses sent to its window will be printed to stdout as `press N`
/ `release N` lines with the correct numeric keycode, in the order
they happened.
