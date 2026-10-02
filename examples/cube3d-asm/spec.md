A rotating 3D wireframe cube for Linux AArch64, rendered as ASCII art in
the terminal. This is a big step up from previous examples: it needs
3D rotation math with a signed sine/cosine table, orthographic
projection to 2D, and a real line-drawing (rasterization) algorithm —
not just table lookups.

ONLY raw Linux syscalls (no libc). GAS assembly, entry point `_start`,
assembled with `as`, linked with `ld` — no compiler.

Syscall numbers: write=64, nanosleep=101, exit_group=94.

## Data to embed

A 64-entry SIGNED sine table, one signed byte each (range -127..127),
representing sin(angle)*127 for angle = 0..2π across 64 steps. Embed
these exact values as `.byte` (they will be interpreted as signed
8-bit when you use them, e.g. via `ldrsb`):
```
0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12
```
To get cos(angle) for the same angle index `t` (0..63), look up
`sine_table[(t + 16) & 63]` — cosine is sine shifted by a quarter
period (16 steps out of 64).

## The cube

8 vertices (x, y, z), a cube of half-size 15 centered at the origin:
```
v0 = (-15,-15,-15)   v1 = (15,-15,-15)   v2 = (15,15,-15)   v3 = (-15,15,-15)
v4 = (-15,-15, 15)   v5 = (15,-15, 15)   v6 = (15,15, 15)   v7 = (-15,15, 15)
```
12 edges (pairs of vertex indices), connecting them into a cube:
```
0-1, 1-2, 2-3, 3-0,   4-5, 5-6, 6-7, 7-4,   0-4, 1-5, 2-6, 3-7
```

## Per-frame algorithm

Screen: 60 columns x 20 rows, character grid, background = space,
line pixels drawn as `#`.

For frame counter `t` = 0 to 63 (one full rotation, 64 frames total,
then stop):

1. **Rotate around TWO axes** (X then Y) for a real tumbling look —
   a single-axis rotation under orthographic projection just looks
   like a rectangle stretching, not a 3D cube, so this uses two
   different angles:
   - `angle_a = t & 63` (X-axis angle), `angle_b = (t*2) & 63` (Y-axis
     angle, rotates twice as fast — gives a proper tumble, not a
     synchronized spin)
   - `sa = sine_table[angle_a]`, `ca = sine_table[(angle_a+16)&63]`
   - `sb = sine_table[angle_b]`, `cb = sine_table[(angle_b+16)&63]`
   - For each of the 8 vertices (x, y, z), apply X-axis rotation
     first, then Y-axis rotation on the result:
     ```
     // step 1: rotate around X axis (affects y,z; x unchanged)
     y1 = (y*ca - z*sa) >> 7          // asr, signed, fixed-point unscale
     z1 = (y*sa + z*ca) >> 7          // you DO need this intermediate z1

     // step 2: rotate around Y axis (affects x,z1; y1 unchanged)
     x2 = (x*cb + z1*sb) >> 7
     y2 = y1                           // Y-axis rotation doesn't touch y
     ```
     (you don't need the final z after step 2 — orthographic
     projection ignores depth, only x2 and y2 matter)
   - Project to screen coordinates:
     - `screen_col = 30 + x2`
     - `screen_row = 10 + (y2 >> 1)` (the extra `>>1` compensates for
       terminal characters being taller than they are wide)
   - Store these 8 (screen_col, screen_row) pairs somewhere (registers
     or a small stack/memory buffer of 8 points, 2 bytes each is
     enough) — you'll need all 8 before drawing edges.

2. **Clear an in-memory 60x20 character buffer** to spaces (this is
   your framebuffer, separate from the terminal — you build the full
   picture in memory first, then write it all at once).

3. **Draw all 12 edges** into that buffer using integer Bresenham line
   drawing (no division, no floating point) between each edge's two
   projected (screen_col, screen_row) points. Standard algorithm:
   ```
   draw_line(x0, y0, x1, y1):
       dx = abs(x1 - x0)
       sx = (x0 < x1) ? 1 : -1
       dy = -abs(y1 - y0)
       sy = (y0 < y1) ? 1 : -1
       err = dx + dy
       x = x0; y = y0
       loop:
           if 0 <= x < 60 and 0 <= y < 20: buffer[y][x] = '#'
           if x == x1 and y == y1: break
           e2 = 2 * err
           if e2 >= dy: err += dy; x += sx
           if e2 <= dx: err += dx; y += sy
   ```
   (the bounds check `0<=x<60, 0<=y<20` is important — always check
   before writing to the buffer, don't assume points stay in range)

4. **Emit the frame**: build one output buffer containing (a) on frame
   0 only, the 4 bytes ESC[2J (0x1B,0x5B,0x32,0x4A) to clear the
   screen once, (b) always the 3 bytes ESC[H (0x1B,0x5B,0x48) to
   reset cursor position, (c) the 20 rows of 60 characters each from
   your framebuffer, each row followed by a newline (0x0A). Write it
   all with ONE write syscall (fd=1).

5. Sleep 50ms between frames using nanosleep: a struct in memory of
   {tv_sec=0 (8 bytes), tv_nsec=50000000 (8 bytes)}, pointer in x0,
   NULL in x1, syscall 101.

6. Increment t, loop until t reaches 64, then call exit_group(0). The
   program must exit cleanly, not hang, not crash.

The visible result should be a wireframe cube outline that visibly
rotates and changes shape (its silhouette morphs as it turns) across
the 64 frames — not a static image, and not garbage/noise.
