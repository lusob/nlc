#!/usr/bin/env python3
import sys, subprocess

FONT_BYTES = [14,17,17,31,17,17,17,30,17,17,30,17,17,30,15,16,16,16,16,16,15,30,17,17,17,17,17,30,31,16,16,30,16,16,31,31,16,16,30,16,16,16,15,16,16,23,17,17,15,17,17,17,31,17,17,17,31,4,4,4,4,4,31,7,2,2,2,2,18,12,17,18,20,24,20,18,17,16,16,16,16,16,16,31,17,27,21,17,17,17,17,17,25,21,19,17,17,17,14,17,17,17,17,17,14,30,17,17,30,16,16,16,14,17,17,17,21,18,13,30,17,17,30,20,18,17,15,16,16,14,1,1,30,31,4,4,4,4,4,4,17,17,17,17,17,17,14,17,17,17,17,17,10,4,17,17,17,21,21,27,17,17,17,10,4,10,17,17,17,17,10,4,4,4,4,31,1,2,4,8,16,31,14,17,19,21,25,17,14,4,12,4,4,4,4,31,14,17,1,2,4,8,31,30,1,1,14,1,1,30,2,6,10,18,31,2,2,31,16,16,30,1,1,30,14,16,16,30,17,17,14,31,1,2,4,8,16,16,14,17,17,14,17,17,14,14,17,17,15,1,1,14,0,0,0,0,0,0,0,0,0,0,31,0,0,0,0,4,0,0,0,4,0,4,4,4,4,4,0,4,17,1,2,4,8,16,17]

MESSAGE = [6,17,4,4,19,8,13,6,18,36,19,14,36,19,7,4,36,3,4,12,14,18,2,4,13,4,36,37,36,27,26,26,40,36,7,0,13,3,36,22,17,8,19,19,4,13,36,0,0,17,2,7,32,30,36,0,18,18,4,12,1,11,24,36,37,36,25,4,17,14,36,11,8,1,2,36,25,4,17,14,36,2,14,12,15,8,11,4,17,36,37,36,2,14,3,4,3,36,21,8,0,36,0,8,36,11,14,14,15,36,4,13,6,8,13,4,4,17,8,13,6,36,37,36,2,11,0,20,3,4,36,2,14,3,4,36,37,36]

SCALE = 3
GLYPH_W = 5
GLYPH_H = 7
ADVANCE = (GLYPH_W + 1) * SCALE
Y_OFFSET = 9
SCROLL_SPEED = 4
WIN_W, WIN_H = 300, 40

def reference_grid(t):
    scroll_offset = t * SCROLL_SPEED
    grid = [[False] * WIN_W for _ in range(WIN_H)]
    for i, glyph_idx in enumerate(MESSAGE):
        char_x = i * ADVANCE - scroll_offset
        if char_x + GLYPH_W * SCALE < 0 or char_x >= WIN_W:
            continue
        rows = FONT_BYTES[glyph_idx*7 : glyph_idx*7+7]
        for row in range(GLYPH_H):
            b = rows[row]
            for col in range(GLYPH_W):
                if b & (1 << (4 - col)):
                    for dy in range(SCALE):
                        for dx in range(SCALE):
                            x = char_x + col*SCALE + dx
                            y = Y_OFFSET + row*SCALE + dy
                            if 0 <= x < WIN_W and 0 <= y < WIN_H:
                                grid[y][x] = True
    return grid

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])

    dims = subprocess.run(["identify", "-format", "%w %h", png_path], capture_output=True, text=True).stdout.split()
    w, h = int(dims[0]), int(dims[1])
    if w < 299 or h < 39:
        fail(f"t={t}: image too small: {w}x{h}")
    raw = subprocess.run(["convert", png_path, "-depth", "8", "rgb:-"], capture_output=True).stdout

    def bright(x, y):
        if x < 0 or x >= w or y < 0 or y >= h:
            return False
        i = (y * w + x) * 3
        if i + 2 >= len(raw):
            return False
        return raw[i] > 150 and raw[i+1] > 150 and raw[i+2] > 150

    expected = reference_grid(t)
    exp_on = sum(1 for row in expected for v in row if v)
    if exp_on == 0:
        fail(f"t={t}: reference itself is blank (bad checkpoint choice, not a real failure) — pick a different t")

    hit = 0
    for y in range(WIN_H):
        for x in range(WIN_W):
            if expected[y][x] and bright(x, y):
                hit += 1
    frac = hit / exp_on

    # Also count actual bright pixels in the image to catch "everything is lit" cheating.
    total_bright = sum(1 for y in range(0, h, 2) for x in range(0, w, 2) if bright(x, y))
    total_bright_frac = total_bright / ((w//2) * (h//2))

    if frac < 0.85:
        fail(f"t={t}: only {frac*100:.1f}% of {exp_on} expected text pixels were bright. Image doesn't match expected scroll position.")

    if total_bright_frac > 0.5:
        fail(f"t={t}: {total_bright_frac*100:.1f}% of the whole window is bright — looks filled, not text.")

    print(f"t={t}: OK, {frac*100:.1f}% of {exp_on} expected text pixels matched, overall brightness {total_bright_frac*100:.1f}% (looks like real scrolled text).")
    sys.exit(0)

if __name__ == "__main__":
    main()
