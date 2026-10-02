MILESTONE 5 of an X11 demoscene demo, Linux AArch64, raw syscalls only
(no libc), GAS assembly, entry `_start`, `as`+`ld`, no compiler. This
milestone is INDEPENDENT of the cube milestones — a classic demoscene
horizontal text scroller ("greetings" banner) in its own small window.
No new X11 opcodes beyond what you already know (CreateWindow,
MapWindow, CreateGC, PolyFillRectangle) — this milestone is about
correct bitmap-font + scrolling logic, not new protocol mechanics.

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
`root_depth` = u8 at `buffer[root_offset+38]`.

## Resource IDs

```
window_id = resource_id_base | 1
gc_black  = resource_id_base | 2   (background)
gc_white  = resource_id_base | 3   (text)
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1, 32 bytes)

`depth=root_depth, window_id, parent=root_window_id, x=0,y=0,
width=300, height=40, border-width=0, class=1, visual=root_visual_id,
value-mask=0`.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — same critical reason as previous
milestones.

## Two GCs (CreateGC, opcode 55, 20 bytes each)

`gc_black`: foreground=0x00000000. `gc_white`: foreground=0x00FFFFFF.
(same 20-byte shape as before: cid, drawable=window_id,
value-mask=0x00000004, value=color)

## Font data: 41 glyphs, 5 columns x 7 rows each, 1 byte per row

Each byte's bit 4 = leftmost column, bit 0 = rightmost column (only
bits 4..0 are meaningful, bits 7..5 are always 0). Embed this table of
41*7 = 287 bytes EXACTLY as given, in this order (glyph 0 = 'A', glyph
1 = 'B', ... following the order string below):

Order string (which glyph index is which character): `ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -:!%`
(so glyph index 0='A', 1='B', ..., 25='Z', 26='0', ..., 35='9', 36=' ', 37='-', 38=':', 39='!', 40='%')

Font bytes (287 decimal values, 7 per glyph, in glyph order 0..40):
```
14,17,17,31,17,17,17,
30,17,17,30,17,17,30,
15,16,16,16,16,16,15,
30,17,17,17,17,17,30,
31,16,16,30,16,16,31,
31,16,16,30,16,16,16,
15,16,16,23,17,17,15,
17,17,17,31,17,17,17,
31,4,4,4,4,4,31,
7,2,2,2,2,18,12,
17,18,20,24,20,18,17,
16,16,16,16,16,16,31,
17,27,21,17,17,17,17,
17,25,21,19,17,17,17,
14,17,17,17,17,17,14,
30,17,17,30,16,16,16,
14,17,17,17,21,18,13,
30,17,17,30,20,18,17,
15,16,16,14,1,1,30,
31,4,4,4,4,4,4,
17,17,17,17,17,17,14,
17,17,17,17,17,10,4,
17,17,17,21,21,27,17,
17,17,10,4,10,17,17,
17,17,10,4,4,4,4,
31,1,2,4,8,16,31,
14,17,19,21,25,17,14,
4,12,4,4,4,4,31,
14,17,1,2,4,8,31,
30,1,1,14,1,1,30,
2,6,10,18,31,2,2,
31,16,16,30,1,1,30,
14,16,16,30,17,17,14,
31,1,2,4,8,16,16,
14,17,17,14,17,17,14,
14,17,17,15,1,1,14,
0,0,0,0,0,0,0,
0,0,0,31,0,0,0,
0,4,0,0,0,4,0,
4,4,4,4,4,0,4,
17,1,2,4,8,16,17,
```

## Message: 138 glyph indices (already converted from text — just use
these numbers directly, you do NOT need any ASCII-to-glyph lookup)

Embed this exact array of 138 byte values as the scrolling message:
```
6,17,4,4,19,8,13,6,18,36,19,14,36,19,7,4,36,3,4,12,14,18,2,4,13,4,36,37,36,27,26,26,40,36,7,0,13,3,36,22,17,8,19,19,4,13,36,0,0,17,2,7,32,30,36,0,18,18,4,12,1,11,24,36,37,36,25,4,17,14,36,11,8,1,2,36,25,4,17,14,36,2,14,12,15,8,11,4,17,36,37,36,2,14,3,4,3,36,21,8,0,36,0,8,36,11,14,14,15,36,4,13,6,8,13,4,4,17,8,13,6,36,37,36,2,11,0,20,3,4,36,2,14,3,4,36,37,36
```

## Per-frame algorithm (t = 0 to 149, 150 frames total, then stop)

Constants: `SCALE=3` (each font pixel becomes a 3x3 screen block),
`GLYPH_W=5`, `GLYPH_H=7`, `ADVANCE=(GLYPH_W+1)*SCALE=18` (pixels
between the start of one character and the next), `Y_OFFSET=9`
(vertical position of the glyph's top row on screen), `SCROLL_SPEED=4`
(pixels per frame). Frame delay is 80ms (see step 5) — do not use a
shorter delay, it needs to stay visible long enough for external
tools to reliably capture each frame.

1. `scroll_offset = t * SCROLL_SPEED`
2. **Clear the window**: PolyFillRectangle (opcode 70, 20-byte shape
   you already know) with gc_black, full window rect (0,0,300,40).
3. **Build ONE PolyFillRectangle request containing every visible
   "on" pixel-block of every visible character, all at once** (like
   you've done before with multiple rectangles in one request):
   - For `i` = 0 to 137 (the 138 characters of the message, in
     order):
     - `char_x = i * ADVANCE - scroll_offset`
     - If `char_x + (GLYPH_W*SCALE) < 0` OR `char_x >= 300`: this
       character is entirely off-screen, skip it (don't waste a
       rectangle on it).
     - Otherwise, look up glyph index `message[i]`, and its 7 font
       bytes (glyph_index*7 .. glyph_index*7+6 in the font table).
     - For `row` = 0 to 6, for `col` = 0 to 4: if bit `(4-col)` of
       that row's byte is set, this pixel is "on" — append ONE
       rectangle to the request: x=`char_x + col*SCALE`,
       y=`Y_OFFSET + row*SCALE`, width=`SCALE`, height=`SCALE`.
   - Send this single PolyFillRectangle (opcode 70) request with
     gc_white and however many rectangles you collected (could be a
     few hundred — that's fine, one request, just make the length
     field match: `length = 3 (header units: opcode+drawable+gc,
     where drawable+gc are 2 units) + 2*num_rects` — wait, be
     precise: total request bytes = 4 (opcode+unused+length) + 4
     (drawable) + 4 (gc) + 8*num_rects. The `length` field value is
     `(12 + 8*num_rects) / 4` = `3 + 2*num_rects`.
4. Print `frame=N\n` to stdout (N = t, decimal ASCII, hand-rolled
   itoa — values go up to 149, so you need 3-digit output support,
   no leading zeros).
5. Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
6. Increment t, loop until t=150, then sleep 1 more second, then
   exit_group(0).

Result: white pixel-art text scrolling right-to-left across a black
300x40 window, readable if you look closely (it's blocky 5x7-pixel
font scaled 3x), looping through the greeting message.
