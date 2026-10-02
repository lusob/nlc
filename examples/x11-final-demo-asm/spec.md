FINAL DEMO: combine three already-proven effects (fire, rotating
shaded cube, text scroller) into ONE X11 program with ONE window,
Linux AArch64, raw syscalls only (no libc). GAS assembly, entry
`_start`, `as`+`ld`, no compiler. This is pure integration — each
sub-effect's algorithm is already proven correct individually, this
spec just combines them with consistent resource IDs and a shared
per-frame draw sequence.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

## Connect + handshake (identical to every previous milestone, repeat verbatim)

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
`root_depth` = u8 at `buffer[root_offset+38]` (24 on this server).

## Window layout

ONE window, 300 wide x 340 tall:
- Rows y=0..299 (300x300 area): fire background (bottom half) + rotating cube on top.
- Rows y=300..339 (300x40 band): scrolling text banner.

## Resource IDs

```
window_id  = resource_id_base | 1
gc_black   = resource_id_base | 2   (background clear, scroller clear, cube edges)
gc_putimg  = resource_id_base | 3   (used for the fire PutImage call — its color doesn't matter)
gc_red     = resource_id_base | 4   (cube face)
gc_cyan    = resource_id_base | 5   (cube face)
gc_green   = resource_id_base | 6   (cube face)
gc_magenta = resource_id_base | 7   (cube face)
gc_blue    = resource_id_base | 8   (cube face)
gc_yellow  = resource_id_base | 9   (cube face)
gc_white   = resource_id_base | 10  (scroller text)
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1, 32 bytes)

`depth=root_depth, window_id, parent=root_window_id, x=0,y=0,
width=300, height=340, border-width=0, class=1, visual=root_visual_id,
value-mask=0`.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — CRITICAL, same reason as every previous
milestone.

## Nine GCs (CreateGC, opcode 55, 20 bytes each — same shape as always: cid, drawable=window_id, value-mask=0x00000004, value=color)

```
gc_black:   0x00000000
gc_putimg:  0x00000000   (unused color, PutImage ignores GC foreground for ZPixmap)
gc_red:     0x00FF0000
gc_cyan:    0x0000FFFF
gc_green:   0x0000FF00
gc_magenta: 0x00FF00FF
gc_blue:    0x000000FF
gc_yellow:  0x00FFFF00
gc_white:   0x00FFFFFF
```

## Data table 1: 64-entry signed sine table (for the cube), one signed byte each

```
0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12
```
cos(angle) = sine_table[(angle+16)&63].

## Cube data

8 vertices, half-size 100, centered at (150,150) in the 300x300 area:
```
v0=(-100,-100,-100) v1=(100,-100,-100) v2=(100,100,-100) v3=(-100,100,-100)
v4=(-100,-100,100)  v5=(100,-100,100)  v6=(100,100,100)  v7=(-100,100,100)
```
6 faces (vertex indices in perimeter order) with their GC:
```
bottom=[0,1,5,4] gc_red   top=[3,7,6,2] gc_cyan   front=[4,5,6,7] gc_green
back=[1,0,3,2] gc_magenta  left=[0,4,7,3] gc_blue   right=[5,1,2,6] gc_yellow
```
12 edges: `0-1,1-2,2-3,3-0, 4-5,5-6,6-7,7-4, 0-4,1-5,2-6,3-7`

## Data table 2: fire palette, 256 entries x 3 bytes (R,G,B) = 768 bytes

```
0,0,0,3,0,0,6,0,0,9,0,0,12,0,0,15,0,0,18,0,0,21,0,0,24,0,0,27,0,0,30,0,0,33,0,0,36,0,0,39,0,0,42,0,0,45,0,0,48,0,0,51,0,0,54,0,0,57,0,0,60,0,0,63,0,0,66,0,0,69,0,0,72,0,0,75,0,0,78,0,0,81,0,0,84,0,0,87,0,0,90,0,0,93,0,0,96,0,0,99,0,0,102,0,0,105,0,0,108,0,0,111,0,0,114,0,0,117,0,0,120,0,0,123,0,0,126,0,0,129,0,0,132,0,0,135,0,0,138,0,0,141,0,0,144,0,0,147,0,0,150,0,0,153,0,0,156,0,0,159,0,0,162,0,0,165,0,0,168,0,0,171,0,0,174,0,0,177,0,0,180,0,0,183,0,0,186,0,0,189,0,0,192,0,0,195,0,0,198,0,0,201,0,0,204,0,0,207,0,0,210,0,0,213,0,0,216,0,0,219,0,0,222,0,0,225,0,0,228,0,0,231,0,0,234,0,0,237,0,0,240,0,0,243,0,0,246,0,0,249,0,0,252,0,0,255,0,0,255,3,0,255,6,0,255,9,0,255,12,0,255,15,0,255,18,0,255,21,0,255,24,0,255,27,0,255,30,0,255,33,0,255,36,0,255,39,0,255,42,0,255,45,0,255,48,0,255,51,0,255,54,0,255,57,0,255,60,0,255,63,0,255,66,0,255,69,0,255,72,0,255,75,0,255,78,0,255,81,0,255,84,0,255,87,0,255,90,0,255,93,0,255,96,0,255,99,0,255,102,0,255,105,0,255,108,0,255,111,0,255,114,0,255,117,0,255,120,0,255,123,0,255,126,0,255,129,0,255,132,0,255,135,0,255,138,0,255,141,0,255,144,0,255,147,0,255,150,0,255,153,0,255,156,0,255,159,0,255,162,0,255,165,0,255,168,0,255,171,0,255,174,0,255,177,0,255,180,0,255,183,0,255,186,0,255,189,0,255,192,0,255,195,0,255,198,0,255,201,0,255,204,0,255,207,0,255,210,0,255,213,0,255,216,0,255,219,0,255,222,0,255,225,0,255,228,0,255,231,0,255,234,0,255,237,0,255,240,0,255,243,0,255,246,0,255,249,0,255,252,0,255,255,0,255,255,3,255,255,6,255,255,9,255,255,12,255,255,15,255,255,18,255,255,21,255,255,24,255,255,27,255,255,30,255,255,33,255,255,36,255,255,39,255,255,42,255,255,45,255,255,48,255,255,51,255,255,54,255,255,57,255,255,60,255,255,63,255,255,66,255,255,69,255,255,72,255,255,75,255,255,78,255,255,81,255,255,84,255,255,87,255,255,90,255,255,93,255,255,96,255,255,99,255,255,102,255,255,105,255,255,108,255,255,111,255,255,114,255,255,117,255,255,120,255,255,123,255,255,126,255,255,129,255,255,132,255,255,135,255,255,138,255,255,141,255,255,144,255,255,147,255,255,150,255,255,153,255,255,156,255,255,159,255,255,162,255,255,165,255,255,168,255,255,171,255,255,174,255,255,177,255,255,180,255,255,183,255,255,186,255,255,189,255,255,192,255,255,195,255,255,198,255,255,201,255,255,204,255,255,207,255,255,210,255,255,213,255,255,216,255,255,219,255,255,222,255,255,225,255,255,228,255,255,231,255,255,234,255,255,237,255,255,240,255,255,243,255,255,246,255,255,249,255,255,252,255,255,255
```

## Fire buffers

FIRE_W=300, FIRE_H=150. Two heat buffers in `.bss`, `buf_a` and
`buf_b`, each `FIRE_W*FIRE_H = 45000` bytes, zero-initialized. A
`.data` 4-byte cell `rand_seed` initialized to `12345`. A pixel output
buffer in `.bss` of `FIRE_W*FIRE_H*4 = 180000` bytes.

LCG: `rand_seed = rand_seed * 1103515245 + 12345` (32-bit wraparound
multiply+add). Use `rand_seed >> 16` as "the random value" for each call.

## Data table 3: font, 41 glyphs, 5x7, 1 byte per row (bits 4..0 = leftmost..rightmost)

Order string: `ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -:!%` (glyph 0='A' ... 40='%')
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

## Data table 4: message, 138 glyph indices (no ASCII lookup needed, use directly)

```
6,17,4,4,19,8,13,6,18,36,19,14,36,19,7,4,36,3,4,12,14,18,2,4,13,4,36,37,36,27,26,26,40,36,7,0,13,3,36,22,17,8,19,19,4,13,36,0,0,17,2,7,32,30,36,0,18,18,4,12,1,11,24,36,37,36,25,4,17,14,36,11,8,1,2,36,25,4,17,14,36,2,14,12,15,8,11,4,17,36,37,36,2,14,3,4,3,36,21,8,0,36,0,8,36,11,14,14,15,36,4,13,6,8,13,4,4,17,8,13,6,36,37,36,2,11,0,20,3,4,36,2,14,3,4,36,37,36
```

## Per-frame algorithm (t = 0 to 299, 300 frames total, then stop)

**1. Fire simulation and render** (identical algorithm to the
standalone fire milestone, just bigger: FIRE_W=300, FIRE_H=150):
   - Pick current/next buffer by `t & 1` (0: current=buf_a,next=buf_b; 1: current=buf_b,next=buf_a).
   - Seed bottom row (row `FIRE_H-1=149`) of `next`: for x=0..299: `next[149][x] = 180 + (rand&63)`.
   - Propagate: for y=0..FIRE_H-2, x=0..FIRE_W-1, reading only from `current`:
     `below=current[y+1][x]`, `left`/`right` = horizontal neighbors of row y+1 (wrap at edges: x=0 wraps to FIRE_W-1, x=FIRE_W-1 wraps to 0),
     `avg=(below+left+right)/3`, `cooling=4+(rand&7)`, `next[y][x]=max(0,avg-cooling)`.
   - Render `next` through the palette into the pixel buffer (4 bytes/pixel, `(R<<16)|(G<<8)|B` as u32 LE, byte layout B,G,R,0).
   - **PutImage** (opcode 72) this pixel buffer into the window at `dst-x=0, dst-y=150` (so it fills screen rows 150-299), width=300, height=150, format=2(ZPixmap), depth=24, gc=gc_putimg, drawable=window_id. Fixed header is 24 bytes (opcode,format,length,drawable,gc,width,height,dst-x,dst-y,left-pad,depth,unused) then the 180000-byte pixel payload. `length = (24+180000)/4 = 45006`.

**2. Clear the top half** (screen rows 0-149, where the fire doesn't
   reach): PolyFillRectangle (opcode 70) with gc_black, rect
   (0,0,300,150).

**3. Rotating cube** (identical algorithm to the shaded-cube
   milestone — full two-axis rotation, painter's-algorithm depth
   sort, 6 FillPoly faces then 12 PolySegment edges in black):
   - `angle_a=t&63`, `angle_b=(t*2)&63`, get sa/ca/sb/cb from the sine table.
   - For each of the 8 vertices: `y1=(y*ca-z*sa)>>7`, `z1=(y*sa+z*ca)>>7`, `x2=(x*cb+z1*sb)>>7`, `z2=(-x*sb+z1*cb)>>7`, `y2=y1`, `screen_x=150+x2`, `screen_y=150+y2`, `depth=z2`.
   - Sort the 6 faces by summed depth ascending (lowest first, highest/nearest last — bubble/insertion sort is fine).
   - Draw the 6 faces in that order with FillPoly (opcode 69: drawable,gc,shape=2,coordmode=0,4 points).
   - Draw the 12 edges with ONE PolySegment (opcode 66) request using gc_black.

**4. Scroller** (identical algorithm to the scroller milestone, just
   shifted down by 300 pixels vertically):
   - `SCALE=3, GLYPH_W=5, GLYPH_H=7, ADVANCE=18, Y_OFFSET=309` (was 9,
     now +300 because the scroller band starts at screen y=300),
     `SCROLL_SPEED=4`.
   - `scroll_offset = t * SCROLL_SPEED`.
   - Clear the scroller band: PolyFillRectangle gc_black, rect (0,300,300,40).
   - For each of the 138 message characters, compute `char_x = i*ADVANCE - scroll_offset`, skip if entirely off the 0-300 x-range. For visible ones, look up the glyph's 7 font bytes and emit one rectangle per "on" bit (position `char_x+col*SCALE, Y_OFFSET+row*SCALE`, size SCALE x SCALE). Collect ALL rectangles from ALL visible characters into ONE PolyFillRectangle (opcode 70) request with gc_white.

**5.** Print `frame=N\n` to stdout (N=t, decimal ASCII, up to 3 digits, no leading zeros).
**6.** Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
**7.** Increment t, loop until t=300, then sleep 2 more seconds, then exit_group(0).

Result: a single 300x340 window showing a flickering fire in the
bottom half of the main area, a solid 6-color wireframe-edged cube
rotating on top of it (visible over both the black top half and the
fire), and a scrolling greeting message in a banner below — a
complete, cohesive demoscene piece.
