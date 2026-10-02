MILESTONE 3 of an X11 demoscene demo, for Linux AArch64, raw syscalls
only (no libc). GAS assembly, entry `_start`, assembled with `as`,
linked with `ld` — no compiler. Builds on milestones 1+2 (connect,
handshake, create+map a window, draw with GC): this milestone animates
a rotating 3D wireframe cube inside the real X11 window using real
X11 line-drawing requests (PolySegment) instead of drawing into a
terminal — the X server does the line rasterization for you this
time, you don't need your own Bresenham.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94.

## Connect + handshake (identical to milestones 1 and 2)

AF_UNIX(1) SOCK_STREAM(1) socket, connect to `/tmp/.X11-unix/X0`
(sockaddr_un: 2-byte family=1, 17 ASCII bytes `/tmp/.X11-unix/X0`,
NUL, zero-pad to 108-byte sun_path, total struct 110 bytes,
addrlen=110).

48-byte connection setup request:
```
offset 0:  byte 'l' (0x6c)
offset 1:  byte 0
offset 2:  u16 LE 11
offset 4:  u16 LE 0
offset 6:  u16 LE 18
offset 8:  u16 LE 16
offset 10: u16 LE 0
offset 12: "MIT-MAGIC-COOKIE-1" (18 bytes + 2 zero pad)
offset 32: cookie: @@XAUTH_COOKIE@@
```
Read 8-byte header, then `addl_len*4` more bytes (addl_len = u16 LE at
offset 6) into the same buffer, looping on `read` until complete.
Verify success byte (offset 0) == 1.

Parse (absolute offsets in the combined buffer):
```
offset 12: u32 LE resource_id_base
offset 24: u16 LE vendor_len (v)
offset 29: u8   num_formats
root_offset = 40 + ((vendor_len+3)&~3) + num_formats*8
root_window_id = u32 LE at buffer[root_offset..+4)
root_visual_id = u32 LE at buffer[root_offset+32..+36)
root_depth     = u8  at buffer[root_offset+38]
```

## Resource IDs

```
window_id = resource_id_base | 1
gc_black  = resource_id_base | 2   (background/clear color)
gc_white  = resource_id_base | 3   (line color)
```
Print `window_id=0xXXXXXXXX\n` to stdout immediately after computing it.

## CreateWindow (opcode 1) — 32 bytes, same shape as milestone 2

```
offset 0: u8  opcode=1
offset 1: u8  depth = root_depth (real parsed value)
offset 2: u16 LE length=8
offset 4: u32 LE window_id
offset 8: u32 LE parent = root_window_id
offset 12: i16 LE x=0
offset 14: i16 LE y=0
offset 16: u16 LE width=300
offset 18: u16 LE height=300
offset 20: u16 LE border-width=0
offset 22: u16 LE class=1 (InputOutput)
offset 24: u32 LE visual = root_visual_id (real parsed value)
offset 28: u32 LE value-mask=0
```

## MapWindow (opcode 8) — 8 bytes: opcode, unused, length=2, window_id

Then sleep 300ms (nanosleep, tv_sec=0, tv_nsec=300000000) — same
critical reason as milestone 2: drawing right after Map races the
server's clear-to-background.

## Two Graphics Contexts (CreateGC, opcode 55, 20 bytes each)

```
gc_black: cid=gc_black, drawable=window_id, value-mask=0x00000004 (GCForeground), value=0x00000000 (black)
gc_white: cid=gc_white, drawable=window_id, value-mask=0x00000004 (GCForeground), value=0x00FFFFFF (white)
```
(same 20-byte layout as milestone 2's CreateGC: opcode(1)+unused(1)+length(2)+cid(4)+drawable(4)+value-mask(4)+value(4), length field=5)

## Cube data (reuse exactly, same numbers as the terminal cube milestone)

8 vertices, half-size 100 this time (bigger, since we're drawing real
pixels not characters), centered at origin:
```
v0=(-100,-100,-100) v1=(100,-100,-100) v2=(100,100,-100) v3=(-100,100,-100)
v4=(-100,-100,100)  v5=(100,-100,100)  v6=(100,100,100)  v7=(-100,100,100)
```
12 edges: `0-1,1-2,2-3,3-0, 4-5,5-6,6-7,7-4, 0-4,1-5,2-6,3-7`

64-entry signed sine table (same as before, one signed byte each):
```
0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12
```
cos(angle) = sine_table[(angle+16)&63].

## Per-frame animation (t = 0 to 63, 64 frames total, then stop)

1. `angle_a = t & 63`, `angle_b = (t*2) & 63`
   `sa=sine[angle_a]`, `ca=sine[(angle_a+16)&63]`, `sb=sine[angle_b]`, `cb=sine[(angle_b+16)&63]`
2. For each of the 8 vertices (x,y,z), same two-stage rotation as before:
   ```
   y1 = (y*ca - z*sa) >> 7      // asr, signed
   z1 = (y*sa + z*ca) >> 7
   x2 = (x*cb + z1*sb) >> 7
   y2 = y1
   screen_x = 150 + x2          // window is 300x300, center at (150,150)
   screen_y = 150 + y2          // NO extra >>1 this time — real pixels are square, unlike terminal chars
   ```
   Store all 8 (screen_x, screen_y) pairs — you need all of them before drawing.
3. **Clear the window**: send PolyFillRectangle (opcode 70, same 20-byte
   shape as milestone 2) with gc_black, covering the whole window
   (rect x=0,y=0,width=300,height=300).
4. **Draw the cube**: send ONE PolySegment request (opcode 66)
   containing all 12 edges as 12 SEGMENT structures back to back:
   ```
   offset 0: u8  opcode=66
   offset 1: u8  unused=0
   offset 2: u16 LE length = 4 + 12*2   (in 4-byte units: header(1 unit) + drawable(1) + gc(1) + 12 segments * 2 units each = 4 + 24 = 28)
   offset 4: u32 LE drawable = window_id
   offset 8: u32 LE gc = gc_white
   offset 12: then 12 SEGMENT structures, 8 bytes each, one per edge, in the same order as the edge list above:
              i16 LE x1, i16 LE y1, i16 LE x2, i16 LE y2
              (x1,y1) = the projected screen coords of the edge's first vertex, (x2,y2) = the second vertex
   ```
   Total request size = 12 (header+drawable+gc) + 12*8 (segments) = 12+96 = 108 bytes.
5. Print `frame=N\n` to stdout (N = t as a plain decimal ASCII number,
   no leading zeros, e.g. "frame=8\n" — implement decimal itoa by hand
   for values 0-63, two digits max) — print this AFTER sending the
   PolySegment request for this frame, so it signals "this frame is
   now drawn and visible".
6. Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
7. Increment t, loop until t=64, then sleep 2 more seconds (keep the
   final frame visible) and exit_group(0).

The visible result: a wireframe cube that rotates and tumbles inside
the real X11 window (white lines on black background), for 64 frames,
then the program exits cleanly.
