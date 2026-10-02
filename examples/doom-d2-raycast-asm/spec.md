MILESTONE D2 of a Doom-style raycaster project, Linux AArch64, raw
syscalls only (no libc). GAS assembly, entry `_start`, `as`+`ld`, no
compiler. This milestone: render ONE static first-person raycasted
frame (fixed player position/angle, no movement, no input yet) into
an X11 window, using a simplified "raymarching" technique (fixed-step
ray advancement, NOT classic DDA) — this avoids needing any division
inside the per-step loop, only one division per screen column at the
very end.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

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

## Resource IDs

```
window_id  = resource_id_base | 1
gc_ceiling = resource_id_base | 2   (dark blue-gray, 0x00303050)
gc_floor   = resource_id_base | 3   (dark brown, 0x00504030)
gc_wall    = resource_id_base | 4   (gray, 0x00909090)
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1, 32 bytes, value-mask=0 — no event mask needed this milestone)

`depth=root_depth, window_id, parent=root_window_id, x=0,y=0,
width=300, height=200, border-width=0, class=1, visual=root_visual_id,
value-mask=0`.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — same critical reason as every previous
milestone.

## Three GCs (CreateGC, opcode 55, 20 bytes each — same shape as always)

`gc_ceiling`: foreground=0x00303050. `gc_floor`: foreground=0x00504030.
`gc_wall`: foreground=0x00909090.

## Data table: 256-entry signed sine table, one signed byte each (range -127..127)

```
0,3,6,9,12,16,19,22,25,28,31,34,37,40,43,46,49,51,54,57,60,63,65,68,71,73,76,78,81,83,85,88,90,92,94,96,98,100,102,104,106,107,109,111,112,113,115,116,117,118,120,121,122,122,123,124,125,125,126,126,126,127,127,127,127,127,127,127,126,126,126,125,125,124,123,122,122,121,120,118,117,116,115,113,112,111,109,107,106,104,102,100,98,96,94,92,90,88,85,83,81,78,76,73,71,68,65,63,60,57,54,51,49,46,43,40,37,34,31,28,25,22,19,16,12,9,6,3,0,-3,-6,-9,-12,-16,-19,-22,-25,-28,-31,-34,-37,-40,-43,-46,-49,-51,-54,-57,-60,-63,-65,-68,-71,-73,-76,-78,-81,-83,-85,-88,-90,-92,-94,-96,-98,-100,-102,-104,-106,-107,-109,-111,-112,-113,-115,-116,-117,-118,-120,-121,-122,-122,-123,-124,-125,-125,-126,-126,-126,-127,-127,-127,-127,-127,-127,-127,-126,-126,-126,-125,-125,-124,-123,-122,-122,-121,-120,-118,-117,-116,-115,-113,-112,-111,-109,-107,-106,-104,-102,-100,-98,-96,-94,-92,-90,-88,-85,-83,-81,-78,-76,-73,-71,-68,-65,-63,-60,-57,-54,-51,-49,-46,-43,-40,-37,-34,-31,-28,-25,-22,-19,-16,-12,-9,-6,-3
```
This is a full 0-360° circle in 256 steps (each step = 1.40625°).
`cos(angle) = sine_table[(angle+64)&255]` (quarter turn = 256/4=64).

## Map data: 8x8 grid, 1=wall, 0=open, one byte per cell (row-major, 64 bytes)

```
1,1,1,1,1,1,1,1,
1,0,0,0,0,0,0,1,
1,0,1,1,0,1,0,1,
1,0,1,0,0,0,0,1,
1,0,0,0,1,1,0,1,
1,0,1,0,0,0,0,1,
1,0,0,0,0,1,0,1,
1,1,1,1,1,1,1,1,
```
(row 0 first, 8 bytes per row, `map[y*8+x]`)

## Fixed-point conventions

Position/distance uses fixed-point scale 256 (so 1 map cell = 256
fixed-point units; to get the integer map cell from a fixed-point
coordinate, arithmetic-shift-right by 8: `cell = fx_coord >> 8`).

Player (fixed, no movement this milestone):
```
player_x_fx = 896     (= 3*256+128, i.e. map position (3.5, ...))
player_y_fx = 384     (= 1*256+128, i.e. map position (..., 1.5))
player_angle = 0      (index into the 256-entry sine table)
```

Screen: `SCREEN_W=300`, `SCREEN_H=200`. `FOV_UNITS=43` (out of 256,
≈60°). `STEP_FX=8` (ray advance per raymarch step). `MAX_STEPS=400`
(safety bound — if no wall found within this many steps, treat it as
"very far", see below). `PROJ = SCREEN_H * 256 = 51200` (projection
constant for wall-height).

## Raycasting algorithm (compute once, since this milestone is a single static frame)

For each screen column `i` = 0 to 299:

1. `angle = (player_angle - FOV_UNITS/2 + (i*FOV_UNITS)/SCREEN_W) & 255`
   (`FOV_UNITS/2` = 21 using integer division; `(i*FOV_UNITS)/SCREEN_W`
   needs one integer division per column — that's fine, it's just one
   per column, not per raymarch-step)
2. `cosv = sine_table[(angle+64)&255]`, `sinv = sine_table[angle]`
   (both signed, -127..127)
3. Raymarch: `dist_fx = 0`, loop up to `MAX_STEPS` times:
   - `dist_fx += STEP_FX`
   - `test_x = player_x_fx + ((dist_fx * cosv) >> 7)` (asr, signed — same fixed-point-unscale pattern used in the cube milestones)
   - `test_y = player_y_fx + ((dist_fx * sinv) >> 7)`
   - `cx = test_x >> 8`, `cy = test_y >> 8` (asr — map cell coordinates; if cx or cy is outside 0..7, treat that cell as a wall (=1), same as the map's border which is already walls anyway)
   - if `map[cy*8+cx] == 1`: wall hit, stop this column's loop, keep this `dist_fx`
   - if the loop finishes all MAX_STEPS without hitting a wall: use `dist_fx = MAX_STEPS*STEP_FX` (=3200) as a fallback
4. `wall_h = PROJ / dist_fx` (real integer division, one per column — e.g. `udiv`). If `wall_h > SCREEN_H`, clamp `wall_h = SCREEN_H`.
5. `wall_top = (SCREEN_H - wall_h) / 2` (asr by 1, since dividing by 2). `wall_bottom = wall_top + wall_h`.
6. Remember `(i, wall_top, wall_bottom)` for this column — you need all 300 before drawing (store in a small buffer, e.g. two 300-entry arrays of 16-bit values, or 300 entries of a small struct).

## Drawing (after computing all 300 columns)

1. **Ceiling**: PolyFillRectangle (opcode 70, 20-byte shape you know)
   with `gc_ceiling`, rect (0,0,300,100) — the top half.
2. **Floor**: PolyFillRectangle with `gc_floor`, rect (0,100,300,100) — the bottom half.
3. **Walls**: build ONE PolyFillRectangle request containing 300
   rectangles (one per column), each `x=i, y=wall_top[i], width=1,
   height=wall_bottom[i]-wall_top[i]`, all with `gc_wall`. Same
   "many rectangles in one request" pattern used in earlier
   milestones. Total request = 4(header)+4(drawable)+4(gc)+300*8(rects)
   = 2412 bytes, `length = 2412/4 = 603`.

## Finish

Print `frame=0\n` to stdout (just this one line — proves the render
completed). Sleep 3 seconds (nanosleep, tv_sec=3, tv_nsec=0) so the
frame stays visible for an external screenshot, then exit_group(0).

Result: a single static first-person view of a small maze — a
receding gray corridor with a dark blue-gray ceiling and dark brown
floor.
