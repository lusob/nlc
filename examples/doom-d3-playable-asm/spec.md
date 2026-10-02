MILESTONE D3 (final) of a Doom-style raycaster project, Linux
AArch64, raw syscalls only (no libc). GAS assembly, entry `_start`,
`as`+`ld`, no compiler. Combines D1 (keyboard input) and D2 (static
raycasting render) into a real playable loop: WASD movement + basic
wall collision, re-rendering the raycast view every frame.

Syscall numbers: socket=198, connect=203, read=63, write=64,
nanosleep=101, exit_group=94, fcntl=25.

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
window_id  = resource_id_base | 1
gc_ceiling = resource_id_base | 2   (0x00303050)
gc_floor   = resource_id_base | 3   (0x00504030)
gc_wall    = resource_id_base | 4   (0x00909090)
```
Print `window_id=0xXXXXXXXX\n` to stdout right after computing it.

## CreateWindow (opcode 1) — WITH an event mask, like D1

```
offset 0: u8 opcode=1
offset 1: u8 depth=root_depth
offset 2: u16 LE length=9
offset 4: u32 LE window_id
offset 8: u32 LE parent=root_window_id
offset 12: i16 LE x=0
offset 14: i16 LE y=0
offset 16: u16 LE width=300
offset 18: u16 LE height=200
offset 20: u16 LE border-width=0
offset 22: u16 LE class=1
offset 24: u32 LE visual=root_visual_id
offset 28: u32 LE value-mask=0x00000800   (CWEventMask)
offset 32: u32 LE value=0x00000003        (KeyPress|KeyRelease)
```
Total request = 36 bytes.

## MapWindow (opcode 8, 8 bytes), then sleep 300ms (nanosleep,
tv_sec=0, tv_nsec=300000000) — critical, same reason as always.

## Three GCs (CreateGC, opcode 55, 20 bytes each, same shape as always)

`gc_ceiling`: 0x00303050. `gc_floor`: 0x00504030. `gc_wall`: 0x00909090.

## Set the socket non-blocking (fcntl, syscall 25)

`fcntl(fd, F_SETFL=4, O_NONBLOCK=0x800)`: x0=fd, x1=4, x2=0x800, x8=25,
svc #0. After this, reads on the socket return immediately (negative
value = no data pending right now, not an error to report).

## Data table 1: 256-entry signed sine table (identical to D2)

```
0,3,6,9,12,16,19,22,25,28,31,34,37,40,43,46,49,51,54,57,60,63,65,68,71,73,76,78,81,83,85,88,90,92,94,96,98,100,102,104,106,107,109,111,112,113,115,116,117,118,120,121,122,122,123,124,125,125,126,126,126,127,127,127,127,127,127,127,126,126,126,125,125,124,123,122,122,121,120,118,117,116,115,113,112,111,109,107,106,104,102,100,98,96,94,92,90,88,85,83,81,78,76,73,71,68,65,63,60,57,54,51,49,46,43,40,37,34,31,28,25,22,19,16,12,9,6,3,0,-3,-6,-9,-12,-16,-19,-22,-25,-28,-31,-34,-37,-40,-43,-46,-49,-51,-54,-57,-60,-63,-65,-68,-71,-73,-76,-78,-81,-83,-85,-88,-90,-92,-94,-96,-98,-100,-102,-104,-106,-107,-109,-111,-112,-113,-115,-116,-117,-118,-120,-121,-122,-122,-123,-124,-125,-125,-126,-126,-126,-127,-127,-127,-127,-127,-127,-127,-126,-126,-126,-125,-125,-124,-123,-122,-122,-121,-120,-118,-117,-116,-115,-113,-112,-111,-109,-107,-106,-104,-102,-100,-98,-96,-94,-92,-90,-88,-85,-83,-81,-78,-76,-73,-71,-68,-65,-63,-60,-57,-54,-51,-49,-46,-43,-40,-37,-34,-31,-28,-25,-22,-19,-16,-12,-9,-6,-3
```
`cos(angle) = sine_table[(angle+64)&255]`.

## Data table 2: 8x8 map, identical to D2

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

## Persistent state (in `.data`, updated across frames)

```
player_x_fx = 896      (starting value, same as D2: map (3.5,...))
player_y_fx = 384       (map (...,1.5))
player_angle = 0         (0-255)
key_forward  = 0         (0 or 1, byte flag)
key_backward = 0
key_turn_left = 0
key_turn_right = 0
```

## Key mapping

`w`=keycode 25 → forward. `s`=keycode 39 → backward. `a`=keycode 38 →
turn left. `d`=keycode 40 → turn right. Any other keycode: ignore.

## Main loop (t = 0 to 199, 200 frames, then stop)

**1. Poll input**: in an inner loop, call `read(fd, buf, 4096)`
   repeatedly until it returns a negative value (no more data). For
   each 32-byte chunk received: let `etype = buf[0] & 0x7f`, `keycode
   = buf[1]`.
   - Also print the raw event for debugging, exactly like D1 did:
     if `etype==2`: print `press ` + decimal(keycode) + `\n`. If
     `etype==3`: print `release ` + decimal(keycode) + `\n`. (keep
     this — it's useful for verification and costs nothing)
   - Then update state: if `keycode==25` (w): set `key_forward = 1`
     if `etype==2`, or `0` if `etype==3`. Same pattern for
     `keycode==39`→`key_backward`, `keycode==38`→`key_turn_left`,
     `keycode==40`→`key_turn_right`.

**2. Update player state** based on the CURRENT held-key flags:
   - `TURN_SPEED = 3`, `MOVE_SPEED_FX = 6`.
   - if `key_turn_left`: `player_angle = (player_angle - 3) & 255`.
   - if `key_turn_right`: `player_angle = (player_angle + 3) & 255`.
   - if `key_forward` or `key_backward` (compute a `move_dir` = +1 for
     forward, -1 for backward; if both held, net effect is 0, that's
     fine, just don't move):
     ```
     cosv = sine_table[(player_angle+64)&255]
     sinv = sine_table[player_angle]
     cand_x = player_x_fx + move_dir * ((MOVE_SPEED_FX*cosv) >> 7)
     cand_y = player_y_fx + move_dir * ((MOVE_SPEED_FX*sinv) >> 7)
     ```
     Collision check: `cx = cand_x >> 8`, `cy = cand_y >> 8`. If `cx`
     or `cy` is outside 0..7, OR `map[cy*8+cx] == 1` (wall): DON'T
     move (leave player_x_fx/player_y_fx unchanged this frame).
     Otherwise: `player_x_fx = cand_x`, `player_y_fx = cand_y`.

**3. Raycast + render** — IDENTICAL algorithm to milestone D2, just
   using the current (possibly updated) `player_x_fx`, `player_y_fx`,
   `player_angle` instead of fixed constants:
   - `SCREEN_W=300, SCREEN_H=200, FOV_UNITS=43, STEP_FX=8,
     MAX_STEPS=400, PROJ=51200`.
   - For each column i=0..299: compute angle, raymarch (fixed steps,
     no division inside the loop), get `dist_fx`, then `wall_h =
     PROJ/dist_fx` (clamped to SCREEN_H), `wall_top=(SCREEN_H-wall_h)/2`,
     `wall_bottom=wall_top+wall_h`. Store all 300.
   - Draw: PolyFillRectangle gc_ceiling rect(0,0,300,100). PolyFillRectangle
     gc_floor rect(0,100,300,100). ONE PolyFillRectangle with gc_wall
     containing all 300 column rectangles (x=i,y=wall_top,width=1,
     height=wall_bottom-wall_top).

**4.** Print `frame=N\n` to stdout (N=t, decimal, up to 3 digits).
**5.** Sleep 80ms (nanosleep, tv_sec=0, tv_nsec=80000000).
**6.** Increment t, loop until t=200, then exit_group(0) (no extra
   sleep needed at the end this time, the loop itself already runs
   ~16 seconds).

Result: a real playable-feeling first-person view — hold `w`/`s` to
move forward/backward, `a`/`d` to turn, with the corridor view
updating in real time and the player unable to walk through walls.
