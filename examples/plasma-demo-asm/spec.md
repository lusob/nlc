A classic "textmode demoscene" plasma animation for Linux AArch64, using
ONLY raw Linux syscalls (no libc). GNU assembler (GAS) syntax, entry
point `_start` (not `main`), assembled with `as` and linked with `ld`
(no compiler).

Syscall numbers you need: write=64, nanosleep=101, exit_group=94.

## Data you must embed

A 16-character shading ramp, from "empty" to "dense" (index 0 = emptiest):
```
" .:-=+*#%@X$&8BW"
```
(that's a literal space as index 0, then the 15 characters shown)

A 64-entry sine lookup table, values 0-15 (one byte each), representing
a full sine period, already computed for you — embed these exact 64
values in order as a `.byte` table in your data section:
```
8,8,9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10,9,8,8,7,6,5,5,4,3,3,2,2,1,1,1,0,0,0,0,0,0,0,1,1,1,2,2,3,3,4,5,5,6,7
```

## Algorithm

Grid: 60 columns x 20 rows.

For frame counter `t` = 0, 1, 2, ... up to at least 30 frames (loop at
least 30 times, more is fine, but it MUST eventually stop — do not run
forever):

1. Build one output buffer in memory for this frame:
   - On the very first frame only, start the buffer with the 4 bytes
     `ESC [ 2 J` (0x1B, 0x5B, 0x32, 0x4A) to clear the screen.
   - Then always append 3 bytes `ESC [ H` (0x1B, 0x5B, 0x48) to move
     the cursor to the top-left (so each frame redraws in place).
   - Then for row = 0 to 19, for col = 0 to 59:
     - idx1 = (col*2 + t) & 63        (bitwise AND with 63, table size is 64, this wraps around for free)
     - idx2 = (row*3 + t*2) & 63
     - sum = sine_table[idx1] + sine_table[idx2]     (range 0..30)
     - level = sum >> 1                               (range 0..15, this indexes the ramp)
     - append ramp[level] (one character) to the buffer
     - after the 60th column of each row, append a newline byte (0x0A)
   - Total per-frame content: 1220 bytes of ramp chars + newlines (60*20 chars + 20 newlines), plus the 3-byte cursor-home prefix (plus 4 extra bytes on frame 0 only).
2. Write the whole buffer to fd 1 (stdout) with ONE write syscall for the frame.
3. Sleep briefly between frames using nanosleep with a timespec of
   {tv_sec=0, tv_nsec=50000000} (50ms — roughly 20 frames/second). You
   need a struct in memory: 8 bytes tv_sec (0) followed by 8 bytes
   tv_nsec (50000000), pointer to it in x0, NULL in x1, syscall 101.
4. Increment t by 1 (or 2, your choice, just keep it consistent) and
   loop back to step 1, until you've done at least 30 frames.

After the frame loop ends, call exit_group(0) — the program must exit
cleanly with status 0, not hang, not crash.

This is significantly harder than previous examples: it requires
correct 2D nested loops, table lookups with two different indices per
cell, arithmetic (multiply, add, bitwise AND, shift), a growing frame
counter that changes the pattern over time (so consecutive frames must
visibly differ — an animation, not a static image), and correct binary
struct layout for the nanosleep syscall.
