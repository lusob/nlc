MILESTONE 4 of an X11 demoscene demo, Linux AArch64, raw syscalls only
(no libc), GAS assembly, entry `_start`, `as`+`ld`, no compiler. Builds
on milestone 3 (rotating wireframe cube): upgrade it to a SOLID SHADED
cube — 6 colored faces, correctly occluding each other as it rotates
(painter's algorithm: draw faces back-to-front by depth), with thin
black edges drawn on top for definition. This is classic demoscene
"RGB cube" look.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

## Connect + handshake (identical to milestones 1-3, repeat verbatim)

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
gc_black  = resource_id_base | 2   (background clear + edge outlines)
gc_red    = resource_id_base | 3
gc_cyan   = resource_id_base | 4
gc_green  = resource_id_base | 5
gc_magenta= resource_id_base | 6
gc_blue   = resource_id_base | 7
gc_yellow = resource_id_base | 8
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1, 32 bytes) — same shape as before

```
depth=root_depth, window_id, parent=root_window_id, x=0,y=0,
width=300,height=300, border-width=0, class=1(InputOutput),
visual=root_visual_id, value-mask=0
```

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — CRITICAL, same reason as before (avoid
racing the server's clear-to-background).

## Seven GCs (CreateGC, opcode 55, 20 bytes each — same shape as before)

Each: cid, drawable=window_id, value-mask=0x00000004 (GCForeground), value=color:
```
gc_black:   0x00000000
gc_red:     0x00FF0000
gc_cyan:    0x0000FFFF
gc_green:   0x0000FF00
gc_magenta: 0x00FF00FF
gc_blue:    0x000000FF
gc_yellow:  0x00FFFF00
```

## Cube data

8 vertices, half-size 100:
```
v0=(-100,-100,-100) v1=(100,-100,-100) v2=(100,100,-100) v3=(-100,100,-100)
v4=(-100,-100,100)  v5=(100,-100,100)  v6=(100,100,100)  v7=(-100,100,100)
```
6 faces, each 4 vertex indices in perimeter order (already correctly
wound, just use them as given), with their GC:
```
bottom = [0,1,5,4]  gc_red
top    = [3,7,6,2]  gc_cyan
front  = [4,5,6,7]  gc_green
back   = [1,0,3,2]  gc_magenta
left   = [0,4,7,3]  gc_blue
right  = [5,1,2,6]  gc_yellow
```
12 edges (for the black outline, same as milestone 3):
`0-1,1-2,2-3,3-0, 4-5,5-6,6-7,7-4, 0-4,1-5,2-6,3-7`

64-entry signed sine table (same as before):
```
0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12
```
cos(angle) = sine_table[(angle+16)&63].

## Per-frame algorithm (t = 0 to 63, 64 frames, then stop)

1. `angle_a=t&63`, `angle_b=(t*2)&63`, `sa=sine[angle_a]`,
   `ca=sine[(angle_a+16)&63]`, `sb=sine[angle_b]`, `cb=sine[(angle_b+16)&63]`.
2. For each of the 8 vertices (x,y,z), compute the FULL rotated 3D
   position (this time you need z too, not just x,y — this is new
   compared to milestone 3):
   ```
   y1 = (y*ca - z*sa) >> 7
   z1 = (y*sa + z*ca) >> 7
   x2 = (x*cb + z1*sb) >> 7
   z2 = (-x*sb + z1*cb) >> 7      // NEW: keep this, you need it for depth sorting
   y2 = y1
   screen_x = 150 + x2
   screen_y = 150 + y2
   depth    = z2                  // used only for sorting, not for screen position
   ```
   Store all 8 (screen_x, screen_y, depth) triples.
3. For each of the 6 faces, compute its average depth = sum of its 4
   vertices' `depth` values (don't even need to divide by 4, the sum
   alone sorts the same way).
4. **Sort the 6 faces by average depth ASCENDING** (lowest/most
   negative depth first). This is a tiny sort (6 elements) — a simple
   bubble/insertion sort with compare-and-swap is fine, no need for
   anything fancy. Getting the sort DIRECTION right matters: draw them
   in ascending order (lowest depth drawn FIRST, highest depth drawn
   LAST) — this makes the face closest to the viewer end up on top,
   correctly hiding whatever is behind it.
5. **Clear the window**: PolyFillRectangle (opcode 70, 20 bytes, same
   shape as before) with gc_black, full window rect (0,0,300,300).
6. **Draw the 6 faces in the sorted order from step 4**, each with
   FillPoly (opcode 69):
   ```
   offset 0: u8  opcode = 69
   offset 1: u8  unused = 0
   offset 2: u16 LE length = 4 + 4 (drawable+gc+shape/coordmode) ... + 4 points*1 unit each
             = total request is 16 bytes fixed header + 4 points*4 bytes = 16+16 = 32 bytes = 8 units. So length=8.
   offset 4: u32 LE drawable = window_id
   offset 8: u32 LE gc = <the face's own GC, e.g. gc_red for the bottom face>
   offset 12: u8 shape = 2        (Convex — these quads are always convex, it's a rotated rectangle)
   offset 13: u8 coordinate-mode = 0  (CoordModeOrigin — all points are absolute)
   offset 14: u16 unused = 0
   offset 16: then 4 POINTs, each 4 bytes: i16 LE x, i16 LE y — the face's 4 vertices' (screen_x, screen_y), IN THE SAME ORDER as the face's vertex-index list given above (order matters, it traces the polygon perimeter)
   ```
   Total request = 32 bytes.
7. **Draw the 12 black edges on top**, exactly like milestone 3: ONE
   PolySegment (opcode 66) request with all 12 edges (using the
   projected screen_x,screen_y computed in step 2), using gc_black.
   Same 108-byte request shape as milestone 3 (header 12 bytes +
   12 segments * 8 bytes).
8. Print `frame=N\n` to stdout (N = t, decimal ASCII, hand-rolled
   itoa, no leading zeros) — AFTER sending all the draw requests for
   this frame.
9. Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
10. Increment t, loop until t=64, then sleep 2 more seconds, then
    exit_group(0).

Result: a solid 6-colored cube (red/cyan/green/magenta/blue/yellow
faces, like an RGB cube) with thin black edges, correctly rotating and
self-occluding (you should never see through the cube — whichever
faces are physically in front should visually cover whichever faces
are behind them).
