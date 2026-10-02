#!/usr/bin/env python3
import sys

SINE = [0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12]

VERTS = [
    (-15,-15,-15), (15,-15,-15), (15,15,-15), (-15,15,-15),
    (-15,-15, 15), (15,-15, 15), (15,15, 15), (-15,15, 15),
]
EDGES = [(0,1),(1,2),(2,3),(3,0), (4,5),(5,6),(6,7),(7,4), (0,4),(1,5),(2,6),(3,7)]

COLS, ROWS = 60, 20

def asr(val, n):
    return val >> n  # Python's >> on ints is arithmetic (floor) shift, matches ASR for these magnitudes.

def reference_frame(t):
    angle_a = t & 63
    angle_b = (t * 2) & 63
    sa, ca = SINE[angle_a], SINE[(angle_a + 16) & 63]
    sb, cb = SINE[angle_b], SINE[(angle_b + 16) & 63]
    pts = []
    for (x, y, z) in VERTS:
        y1 = asr(y * ca - z * sa, 7)
        z1 = asr(y * sa + z * ca, 7)
        x2 = asr(x * cb + z1 * sb, 7)
        y2 = y1
        col = 30 + x2
        row = 10 + asr(y2, 1)
        pts.append((col, row))

    buf = [[' '] * COLS for _ in range(ROWS)]

    def plot(x, y):
        if 0 <= x < COLS and 0 <= y < ROWS:
            buf[y][x] = '#'

    def draw_line(x0, y0, x1, y1):
        dx = abs(x1 - x0)
        sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0)
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        x, y = x0, y0
        while True:
            plot(x, y)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x += sx
            if e2 <= dx:
                err += dx
                y += sy

    for (a, b) in EDGES:
        x0, y0 = pts[a]
        x1, y1 = pts[b]
        draw_line(x0, y0, x1, y1)

    return [''.join(row) for row in buf]

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()
    data = data.replace(b"\x1b[2J", b"", 1)
    frames_raw = [f for f in data.split(b"\x1b[H") if f.strip(b"\n")]

    if len(frames_raw) < 20:
        fail(f"Only {len(frames_raw)} frames found (need at least 20).")

    parsed = []
    for fr in frames_raw:
        try:
            text = fr.decode("ascii")
        except UnicodeDecodeError:
            continue
        lines = [l for l in text.split("\n") if l != ""]
        if len(lines) != ROWS:
            continue
        if any(len(l) != COLS or any(c not in " #" for c in l) for l in lines):
            continue
        parsed.append(lines)

    if len(parsed) < 20:
        fail(f"Only {len(parsed)}/{len(frames_raw)} frames were well-formed (60x20, chars in ' #').")

    # Sanity: '#' density per frame must be in a plausible wireframe range, not empty and not filled.
    for i, fr in enumerate(parsed[:20]):
        hashes = sum(row.count('#') for row in fr)
        if hashes < 15:
            fail(f"Frame {i}: only {hashes} '#' pixels — looks empty/broken, not a cube outline.")
        if hashes > 600:
            fail(f"Frame {i}: {hashes} '#' pixels — looks filled/solid, not a wireframe.")

    # Motion check.
    if all(fr == parsed[0] for fr in parsed[1:20]):
        fail("All checked frames are identical — not rotating.")

    # Strict-ish check against a reference implementation of the exact spec'd algorithm,
    # at 4 points across the rotation (t=0,16,32,48 -> frame index == t here).
    checks = [8, 20, 40, 56]
    for t in checks:
        if t >= len(parsed):
            continue
        expected = reference_frame(t)
        actual = parsed[t]
        total = ROWS * COLS
        match = sum(1 for r in range(ROWS) for c in range(COLS) if expected[r][c] == actual[r][c])
        frac = match / total
        if frac < 0.90:
            print(f"Frame t={t}: only {frac*100:.1f}% pixel match vs reference implementation (need >=90%).")
            print("Expected:")
            print("\n".join(expected))
            print("Actual:")
            print("\n".join(actual))
            sys.exit(1)

    print(f"OK: {len(parsed)} well-formed frames, motion detected, reference-matched at t={checks} (>=90% pixel match each).")
    sys.exit(0)

if __name__ == "__main__":
    main()
