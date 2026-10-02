MILESTONE 6 of an X11 demoscene demo, Linux AArch64, raw syscalls only
(no libc), GAS assembly, entry `_start`, `as`+`ld`, no compiler.
INDEPENDENT of the other milestones. Classic demoscene "fire" effect:
a per-pixel heat-diffusion simulation rendered through a palette,
uploaded to the window each frame with PutImage (a new opcode for
this milestone — verified format below, use it exactly as given).

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

## Connect + handshake (identical to previous milestones, repeat verbatim)

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
`root_depth` = u8 at `buffer[root_offset+38]` (will be 24 on this
server — the pixel format below assumes depth 24 / 32 bits-per-pixel,
already confirmed against this server, don't second-guess it).

## Resource IDs

```
window_id = resource_id_base | 1
gc_id     = resource_id_base | 2
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1, 32 bytes)

`depth=root_depth, window_id, parent=root_window_id, x=0,y=0,
width=100, height=50, border-width=0, class=1, visual=root_visual_id,
value-mask=0`.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — same critical reason as previous
milestones (avoid racing the server's clear-to-background).

## CreateGC (opcode 55, 20 bytes) — required by PutImage even though its color doesn't matter here

`cid=gc_id, drawable=window_id, value-mask=0x00000004, value=0x00000000`
(same 20-byte shape as always)

## Data tables to embed

**Fire palette**: 256 entries, 3 bytes each (R,G,B), 768 bytes total.
Embed EXACTLY these 768 decimal values, in order (palette[0] = the
first 3 bytes, palette[1] = the next 3, etc — intensity value i's
color is palette[i]):
```
0,0,0,3,0,0,6,0,0,9,0,0,12,0,0,15,0,0,18,0,0,21,0,0,24,0,0,27,0,0,30,0,0,33,0,0,36,0,0,39,0,0,42,0,0,45,0,0,48,0,0,51,0,0,54,0,0,57,0,0,60,0,0,63,0,0,66,0,0,69,0,0,72,0,0,75,0,0,78,0,0,81,0,0,84,0,0,87,0,0,90,0,0,93,0,0,96,0,0,99,0,0,102,0,0,105,0,0,108,0,0,111,0,0,114,0,0,117,0,0,120,0,0,123,0,0,126,0,0,129,0,0,132,0,0,135,0,0,138,0,0,141,0,0,144,0,0,147,0,0,150,0,0,153,0,0,156,0,0,159,0,0,162,0,0,165,0,0,168,0,0,171,0,0,174,0,0,177,0,0,180,0,0,183,0,0,186,0,0,189,0,0,192,0,0,195,0,0,198,0,0,201,0,0,204,0,0,207,0,0,210,0,0,213,0,0,216,0,0,219,0,0,222,0,0,225,0,0,228,0,0,231,0,0,234,0,0,237,0,0,240,0,0,243,0,0,246,0,0,249,0,0,252,0,0,255,0,0,255,3,0,255,6,0,255,9,0,255,12,0,255,15,0,255,18,0,255,21,0,255,24,0,255,27,0,255,30,0,255,33,0,255,36,0,255,39,0,255,42,0,255,45,0,255,48,0,255,51,0,255,54,0,255,57,0,255,60,0,255,63,0,255,66,0,255,69,0,255,72,0,255,75,0,255,78,0,255,81,0,255,84,0,255,87,0,255,90,0,255,93,0,255,96,0,255,99,0,255,102,0,255,105,0,255,108,0,255,111,0,255,114,0,255,117,0,255,120,0,255,123,0,255,126,0,255,129,0,255,132,0,255,135,0,255,138,0,255,141,0,255,144,0,255,147,0,255,150,0,255,153,0,255,156,0,255,159,0,255,162,0,255,165,0,255,168,0,255,171,0,255,174,0,255,177,0,255,180,0,255,183,0,255,186,0,255,189,0,255,192,0,255,195,0,255,198,0,255,201,0,255,204,0,255,207,0,255,210,0,255,213,0,255,216,0,255,219,0,255,222,0,255,225,0,255,228,0,255,231,0,255,234,0,255,237,0,255,240,0,255,243,0,255,246,0,255,249,0,255,252,0,255,255,0,255,255,3,255,255,6,255,255,9,255,255,12,255,255,15,255,255,18,255,255,21,255,255,24,255,255,27,255,255,30,255,255,33,255,255,36,255,255,39,255,255,42,255,255,45,255,255,48,255,255,51,255,255,54,255,255,57,255,255,60,255,255,63,255,255,66,255,255,69,255,255,72,255,255,75,255,255,78,255,255,81,255,255,84,255,255,87,255,255,90,255,255,93,255,255,96,255,255,99,255,255,102,255,255,105,255,255,108,255,255,111,255,255,114,255,255,117,255,255,120,255,255,123,255,255,126,255,255,129,255,255,132,255,255,135,255,255,138,255,255,141,255,255,144,255,255,147,255,255,150,255,255,153,255,255,156,255,255,159,255,255,162,255,255,165,255,255,168,255,255,171,255,255,174,255,255,177,255,255,180,255,255,183,255,255,186,255,255,189,255,255,192,255,255,195,255,255,198,255,255,201,255,255,204,255,255,207,255,255,210,255,255,213,255,255,216,255,255,219,255,255,222,255,255,225,255,255,228,255,255,231,255,255,234,255,255,237,255,255,240,255,255,243,255,255,246,255,255,249,255,255,252,255,255,255
```

## Heat buffers

W=100, H=50. Reserve TWO buffers in `.bss`, `buf_a` and `buf_b`, each
`W*H = 5000` bytes (one byte per cell, intensity 0-255), both
zero-initialized by the loader (that's what `.bss` gives you for
free). Also reserve a 4-byte `.data` cell `rand_seed` initialized to
`12345` (any nonzero constant works) — this persists across frames.

Also reserve a pixel output buffer in `.bss` of `W*H*4 = 20000` bytes
(4 bytes per pixel, for the PutImage payload each frame).

## Pseudo-random number generator (LCG)

Whenever you need a random 32-bit value: `rand_seed = rand_seed *
1103515245 + 12345` (plain 32-bit multiply+add, let it wrap/overflow
naturally — that's correct, don't try to prevent overflow). Use bits
16-31 of the new `rand_seed` (i.e. `rand_seed >> 16`, keep it as a
32-bit value, you'll mask the low bits you need from that) as "the
random value" for that call.

## Per-frame algorithm (t = 0 to 199, 200 frames total, then stop)

1. Pick which buffer is "current" (read from) and which is "next"
   (write into), based on `t & 1`:
   - if `t & 1 == 0`: current = buf_a, next = buf_b
   - if `t & 1 == 1`: current = buf_b, next = buf_a
   (this alternation is self-consistent frame to frame — each frame
   reads whatever was written last frame)

2. **Seed the bottom row** (row `H-1 = 49`) of `next`: for `x` = 0 to
   99: get a random value `r` (LCG as above), `next[49][x] = 180 +
   (r & 63)` (this gives a value in range 180-243 — the "fire
   source", always hot with some flicker).

3. **Propagate upward** for `y` = 0 to `H-2` (48 rows), for `x` = 0 to
   `W-1` (100 columns), reading ONLY from `current` (never from
   `next` — this is exactly why you have two buffers, to avoid
   read/write ordering bugs):
   ```
   below = current[y+1][x]
   left  = current[y+1][x-1]   if x > 0  else current[y+1][W-1]   (wrap)
   right = current[y+1][x+1]   if x < W-1 else current[y+1][0]     (wrap)
   avg = (below + left + right) / 3        (real integer division by 3, e.g. udiv)
   r = LCG random value
   cooling = 4 + (r & 7)                    (range 4-11, just a bitwise AND, no division needed)
   new_val = avg - cooling
   if new_val < 0 (i.e. cooling > avg): new_val = 0     (clamp, avoid underflow — do this as unsigned-safe: only subtract if avg >= cooling, else store 0)
   next[y][x] = new_val
   ```

4. **Render to the pixel buffer**: for every cell (y,x) in `next` (all
   `W*H` cells), let `v = next[y][x]` (0-255), look up
   `palette[v*3], palette[v*3+1], palette[v*3+2]` (R,G,B), and write 4
   bytes into the pixel output buffer at offset `(y*W+x)*4`:
   byte0=B, byte1=G, byte2=R, byte3=0 (this is the little-endian
   encoding of a 0x00RRGGBB pixel value — you can build it as a u32
   value `(R<<16)|(G<<8)|B` and store it with a single 4-byte store,
   the CPU's little-endian byte order handles the rest correctly).

5. **PutImage** (opcode 72) — send the WHOLE pixel buffer in one
   request:
   ```
   offset 0: u8 opcode = 72
   offset 1: u8 format = 2          (ZPixmap)
   offset 2: u16 LE length = (24 + W*H*4) / 4     (24-byte fixed header + payload, in 4-byte units — with W=100,H=50 this is (24+20000)/4 = 5006)
   offset 4: u32 LE drawable = window_id
   offset 8: u32 LE gc = gc_id
   offset 12: u16 LE width = 100
   offset 14: u16 LE height = 50
   offset 16: i16 LE dst-x = 0
   offset 18: i16 LE dst-y = 0
   offset 20: u8 left-pad = 0
   offset 21: u8 depth = 24
   offset 22: u16 unused = 0
   offset 24: the 20000-byte pixel buffer you built in step 4
   ```
   Total request size = 24 + 20000 = 20024 bytes (well under this
   server's max-request-length, no need to split it).

6. Print `frame=N\n` to stdout (N = t, decimal ASCII, hand-rolled
   itoa, values 0-199 so up to 3 digits, no leading zeros).
7. Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
8. Increment t, loop until t=200, then sleep 1 more second, then
   exit_group(0).

Result: a classic animated fire effect (black at the top fading down
through red/orange/yellow to white-hot at the bottom), flickering and
shifting continuously, in a 100x50 window.
