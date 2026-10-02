A Tetris game for Linux AArch64, raw syscalls only (no libc). GAS
assembly, entry `_start`, `as`+`ld`, no compiler. Goal: keep the
binary as SMALL as possible (reuse subroutines, avoid duplicated
code, pack data tightly) while being fully correct — this is an
explicit size-minimization exercise, not just a functionality one.

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

## Resource IDs

```
window_id = resource_id_base | 1
gc_black  = resource_id_base | 2   (background, value 0x00000000)
gc_I = resource_id_base|3 (0x0000FFFF cyan)   gc_O = resource_id_base|4 (0x00FFFF00 yellow)
gc_T = resource_id_base|5 (0x00800080 purple) gc_S = resource_id_base|6 (0x0000FF00 green)
gc_Z = resource_id_base|7 (0x00FF0000 red)    gc_J = resource_id_base|8 (0x000000FF blue)
gc_L = resource_id_base|9 (0x00FF8000 orange)
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1) — with an event mask (like the Doom milestones)

```
offset 0: u8 opcode=1
offset 1: u8 depth=root_depth
offset 2: u16 LE length=9
offset 4: u32 LE window_id
offset 8: u32 LE parent=root_window_id
offset 12: i16 LE x=0
offset 14: i16 LE y=0
offset 16: u16 LE width=150
offset 18: u16 LE height=300
offset 20: u16 LE border-width=0
offset 22: u16 LE class=1
offset 24: u32 LE visual=root_visual_id
offset 28: u32 LE value-mask=0x00000800   (CWEventMask)
offset 32: u32 LE value=0x00000003        (KeyPress|KeyRelease)
```
Total 36 bytes.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — critical, same reason as always.

## Eight GCs (CreateGC, opcode 55, 20 bytes each, same shape as always)

Colors given above (gc_black through gc_L).

## fcntl non-blocking (syscall 25), same as the Doom milestones

`fcntl(fd, F_SETFL=4, O_NONBLOCK=0x800)`: x0=fd, x1=4, x2=0x800, x8=25, svc #0.

## Data table 1: piece rotation bitmaps — 28 u16 LE values (7 pieces x 4 rotations)

Order: I,O,T,S,Z,J,L (piece type 0-6). Each value is a 4x4 bitmap, bit
`i` (0-15) set means cell `(row=i/4, col=i%4)` is filled. To get the
board cell for a filled bit when the piece's top-left corner is at
board position `(px,py)`: `(x,y) = (px + i%4, py + i/4)`.
```
240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547
```
(store as 28 consecutive u16 LE halfwords; `piece_bits(type,rot) =
table[type*4+rot]`)

## Board and piece state (`.data`, persists across frames)

```
board: 200 bytes, all zero initially (10 wide x 20 tall, one byte per
       cell, `board[row*10+col]`; 0 = empty, 1-7 = locked piece color
       = piece type + 1)
rand_seed: u32 = 12345
piece_type: u32 = <computed at startup, see "spawn" below>
piece_rot: u32 = 0
piece_x: i32 = 3
piece_y: i32 = 0
grav_timer: u32 = 0
game_over: u8 = 0
```

## LCG random (identical pattern to the fire/raycasting milestones)

`rand_seed = rand_seed*1103515245 + 12345` (32-bit wraparound). Next
piece type = `(rand_seed >> 16) % 7` (real modulo by 7, e.g. via
udiv+msub — 7 isn't a power of 2 so you do need a real division here,
just one per piece spawn, not performance-critical).

## Startup: spawn the first piece

Before entering the main loop: call the LCG once to get `piece_type`
(0-6), set `piece_rot=0, piece_x=3, piece_y=0`.

## Collision check subroutine: `collide(type, rot, px, py) -> bool`

For each of the 16 bits in `piece_bits(type,rot)`: if set, compute
`x=px+col, y=py+row`. If `x<0 or x>=10 or y>=20`: return true
(collision — out of bounds). If `y>=0 and board[y*10+x] != 0`: return
true (collision — occupied cell). If neither, continue checking the
rest. If no bit triggered a collision: return false.

## Main loop (t = 0 to 1499, up to 1500 frames — but see "game over" below)

**1. Poll input** (same read-in-a-loop-until-negative pattern as the
   Doom milestones, socket already non-blocking): for each 32-byte
   event chunk, `etype = buf[0]&0x7f`, `keycode = buf[1]`. Print
   `press N\n` / `release N\n` exactly like the Doom milestones (same
   debug convenience). This time input is EDGE-TRIGGERED: only
   KeyPress (`etype==2`) events matter for gameplay, KeyRelease is
   ignored for game logic (only used for the debug print). Track, for
   THIS FRAME ONLY, at most one pending action based on which
   keycodes had a KeyPress in this frame's batch (if multiple
   different action keys were pressed in the same batch, just apply
   the LAST one seen — this is a rare edge case, don't overthink it):
   - keycode 38 ('a') → pending action = "left"
   - keycode 40 ('d') → pending action = "right"
   - keycode 39 ('s') → pending action = "down"
   - keycode 25 ('w') → pending action = "rotate"
   (if no relevant press this frame, no pending action)

**2. Apply the pending action** (if any), only if `game_over==0`:
   - "left": if `!collide(piece_type,piece_rot,piece_x-1,piece_y)`: `piece_x -= 1`
   - "right": if `!collide(piece_type,piece_rot,piece_x+1,piece_y)`: `piece_x += 1`
   - "down": if `!collide(piece_type,piece_rot,piece_x,piece_y+1)`: `piece_y += 1`
   - "rotate": `new_rot = (piece_rot+1) & 3`; if `!collide(piece_type,new_rot,piece_x,piece_y)`: `piece_rot = new_rot`
   (if the collide check fails, just don't apply that action — silently ignored, no error)

**3. Gravity** (only if `game_over==0`): `grav_timer += 1`. If
   `grav_timer >= 6` (GRAVITY constant):
   - `grav_timer = 0`
   - if `!collide(piece_type,piece_rot,piece_x,piece_y+1)`: `piece_y += 1`
   - else (piece can't fall further — LOCK it):
     - For each of the 16 bits in `piece_bits(piece_type,piece_rot)`
       that's set: `x=piece_x+col, y=piece_y+row`; if `0<=y<20`:
       `board[y*10+x] = piece_type+1`.
     - **Clear full lines** (compaction algorithm, single pass,
       bottom-to-top): `write_row = 19`. For `read_row = 19` down to
       `0`: check if `board[read_row]` (10 cells) has ANY empty cell
       (value 0). If it does (row NOT full): if `write_row !=
       read_row`, copy the 10 bytes of `board[read_row*10..+10)` to
       `board[write_row*10..+10)`; then `write_row -= 1`. (If the row
       WAS full, do nothing — don't copy it, don't decrement
       write_row — this is what removes it.) After the loop: for
       `row = write_row` down to `0`: set all 10 bytes of
       `board[row*10..+10)` to 0 (these are the "new" empty rows at
       the top, pushed up by however many lines were cleared).
     - **Spawn next piece**: LCG for next `piece_type`, `piece_rot=0,
       piece_x=3, piece_y=0`. If `collide(piece_type,0,3,0)`: set
       `game_over=1` (the new piece doesn't fit — board is full at
       the top; don't exit the program, just stop updating game state
       for the rest of the frames, keep rendering the final board).

**4. Render**:
   - Clear the whole window: PolyFillRectangle (opcode 70) with
     `gc_black`, rect (0,0,150,300).
   - For EACH of the 7 colors (I,O,T,S,Z,J,L / value 1-7): collect a
     list of rectangles for every board cell with that color value,
     PLUS (only for the CURRENT piece's own color, i.e. color ==
     `piece_type+1`, and only if `game_over==0`) the current falling
     piece's cells too. Each rectangle: `x=col*15, y=row*15, width=15,
     height=15`. If the list for a color is non-empty, send ONE
     PolyFillRectangle request with that color's GC containing all
     its rectangles (same "many rects, one request" pattern used
     throughout — reuse code/a shared subroutine for this across all
     7 colors to keep the binary small, don't duplicate the same
     rectangle-building logic 7 times).

**5.** Print `frame=N\n` to stdout (N=t, decimal, up to 4 digits).
**6.** Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
**7.** Increment t, loop until t=1500, then exit_group(0).

Result: a real playable Tetris — `a`/`d` move left/right, `s` soft
drops, `w` rotates, pieces lock and lines clear, the board fills up
and stops updating (but keeps rendering) on game over. Colors: I=cyan,
O=yellow, T=purple, S=green, Z=red, J=blue, L=orange.
