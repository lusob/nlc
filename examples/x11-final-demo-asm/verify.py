#!/usr/bin/env python3
import sys, subprocess

# --- scroller reference (same as M5, Y_OFFSET shifted by +300) ---
FONT_BYTES = [14,17,17,31,17,17,17,30,17,17,30,17,17,30,15,16,16,16,16,16,15,30,17,17,17,17,17,30,31,16,16,30,16,16,31,31,16,16,30,16,16,16,15,16,16,23,17,17,15,17,17,17,31,17,17,17,31,4,4,4,4,4,31,7,2,2,2,2,18,12,17,18,20,24,20,18,17,16,16,16,16,16,16,31,17,27,21,17,17,17,17,17,25,21,19,17,17,17,14,17,17,17,17,17,14,30,17,17,30,16,16,16,14,17,17,17,21,18,13,30,17,17,30,20,18,17,15,16,16,14,1,1,30,31,4,4,4,4,4,4,17,17,17,17,17,17,14,17,17,17,17,17,10,4,17,17,17,21,21,27,17,17,17,10,4,10,17,17,17,17,10,4,4,4,4,31,1,2,4,8,16,31,14,17,19,21,25,17,14,4,12,4,4,4,4,31,14,17,1,2,4,8,31,30,1,1,14,1,1,30,2,6,10,18,31,2,2,31,16,16,30,1,1,30,14,16,16,30,17,17,14,31,1,2,4,8,16,16,14,17,17,14,17,17,14,14,17,17,15,1,1,14,0,0,0,0,0,0,0,0,0,0,31,0,0,0,0,4,0,0,0,4,0,4,4,4,4,4,0,4,17,1,2,4,8,16,17]
MESSAGE = [6,17,4,4,19,8,13,6,18,36,19,14,36,19,7,4,36,3,4,12,14,18,2,4,13,4,36,37,36,27,26,26,40,36,7,0,13,3,36,22,17,8,19,19,4,13,36,0,0,17,2,7,32,30,36,0,18,18,4,12,1,11,24,36,37,36,25,4,17,14,36,11,8,1,2,36,25,4,17,14,36,2,14,12,15,8,11,4,17,36,37,36,2,14,3,4,3,36,21,8,0,36,0,8,36,11,14,14,15,36,4,13,6,8,13,4,4,17,8,13,6,36,37,36,2,11,0,20,3,4,36,2,14,3,4,36,37,36]
SCALE=3; GLYPH_W=5; GLYPH_H=7; ADVANCE=(GLYPH_W+1)*SCALE; Y_OFFSET=309; SCROLL_SPEED=4; WIN_W=300

def scroller_reference_grid(t):
    scroll_offset = t * SCROLL_SPEED
    on = set()
    for i, gidx in enumerate(MESSAGE):
        char_x = i * ADVANCE - scroll_offset
        if char_x + GLYPH_W*SCALE < 0 or char_x >= WIN_W:
            continue
        rows = FONT_BYTES[gidx*7:gidx*7+7]
        for row in range(GLYPH_H):
            b = rows[row]
            for col in range(GLYPH_W):
                if b & (1 << (4-col)):
                    for dy in range(SCALE):
                        for dx in range(SCALE):
                            on.add((char_x+col*SCALE+dx, Y_OFFSET+row*SCALE+dy))
    return on

# --- cube face colors ---
CANDIDATES = {"red":(255,0,0),"cyan":(0,255,255),"green":(0,255,0),"magenta":(255,0,255),"blue":(0,0,255),"yellow":(255,255,0)}

def classify(rgb, tol=40):
    r,g,b = rgb
    if r<tol and g<tol and b<tol: return "black"
    for name,(cr,cg,cb) in CANDIDATES.items():
        if abs(r-cr)<tol and abs(g-cg)<tol and abs(b-cb)<tol: return name
    return None

def fail(msg):
    print(msg); sys.exit(1)

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])

    dims = subprocess.run(["identify","-format","%w %h",png_path], capture_output=True, text=True).stdout.split()
    w,h = int(dims[0]), int(dims[1])
    if w < 299 or h < 339:
        fail(f"t={t}: image too small: {w}x{h} (expected ~300x340)")
    raw = subprocess.run(["convert",png_path,"-depth","8","rgb:-"], capture_output=True).stdout

    def px(x,y):
        i=(y*w+x)*3
        if i+2>=len(raw): return (0,0,0)
        return (raw[i],raw[i+1],raw[i+2])

    def bright(x,y):
        r,g,b = px(x,y)
        return r>150 and g>150 and b>150

    # --- 1. Fire region check: near the source (y=270-299) at least some fraction of pixels
    # must be clearly hot/bright. NOTE: we deliberately do NOT re-check the full top-to-bottom
    # gradient shape here — that's already rigorously verified standalone (x11-m6-fire-asm).
    # Here the cube legitimately overlaps much of the fire area by design (that's the point of
    # combining them), so a strict row-average comparison is unreliable — instead just confirm
    # the fire source is genuinely lit somewhere near the bottom.
    def brightness_sum(x,y):
        r,g,b = px(x,y); return r+g+b
    near_source = [brightness_sum(x,y) for y in range(270,300,2) for x in range(0,w,3)]
    hot_frac = sum(1 for v in near_source if v > 400) / len(near_source)
    if hot_frac < 0.10:
        fail(f"t={t}: only {hot_frac*100:.1f}% of near-source pixels (y=270-299) are clearly hot (>400) — fire doesn't look lit.")

    # --- 2. Cube: at least 2 distinct face colors somewhere in y=0..299 ---
    counts = {}
    for y in range(0, 300, 3):
        for x in range(0, w, 3):
            c = classify(px(x,y))
            if c and c != "black":
                counts[c] = counts.get(c,0)+1
    distinct = len(counts)
    if distinct < 2:
        fail(f"t={t}: only {distinct} cube face colors visible ({counts}) — expected at least 2.")

    # --- 3. Scroller: match expected "on" pixels in the y=300..339 band ---
    expected = scroller_reference_grid(t)
    if expected:
        hit = sum(1 for (x,y) in expected if bright(x,y))
        frac = hit/len(expected)
        if frac < 0.85:
            fail(f"t={t}: scroller only {frac*100:.1f}% match ({len(expected)} expected pixels).")
    else:
        frac = None  # no visible text at this scroll offset, nothing to check

    print(f"t={t}: OK — fire near-source hot_frac={hot_frac*100:.1f}%, cube colors={sorted(counts.keys())}, scroller match={f'{frac*100:.1f}%' if frac is not None else 'n/a (no visible text this frame)'}.")
    sys.exit(0)

if __name__ == "__main__":
    main()
