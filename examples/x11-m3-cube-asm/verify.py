#!/usr/bin/env python3
import sys, subprocess

SINE = [0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126,127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12,0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126,-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12]
VERTS = [(-100,-100,-100),(100,-100,-100),(100,100,-100),(-100,100,-100),(-100,-100,100),(100,-100,100),(100,100,100),(-100,100,100)]
EDGES = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]

def asr(v, n):
    return v >> n

def reference_points(t):
    a = t & 63
    b = (t * 2) & 63
    sa, ca = SINE[a], SINE[(a + 16) & 63]
    sb, cb = SINE[b], SINE[(b + 16) & 63]
    pts = []
    for (x, y, z) in VERTS:
        y1 = asr(y * ca - z * sa, 7)
        z1 = asr(y * sa + z * ca, 7)
        x2 = asr(x * cb + z1 * sb, 7)
        y2 = y1
        pts.append((150 + x2, 150 + y2))
    return pts

def bresenham(x0, y0, x1, y1):
    pts = []
    dx = abs(x1 - x0); sx = 1 if x0 < x1 else -1
    dy = -abs(y1 - y0); sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    while True:
        pts.append((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x += sx
        if e2 <= dx:
            err += dx; y += sy
    return pts

def expected_line_pixels(t):
    pts = reference_points(t)
    all_pts = set()
    for (a, b) in EDGES:
        x0, y0 = pts[a]
        x1, y1 = pts[b]
        all_pts.update(bresenham(x0, y0, x1, y1))
    return all_pts

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])

    dims = subprocess.run(["identify", "-format", "%w %h", png_path], capture_output=True, text=True).stdout.split()
    if len(dims) != 2:
        fail(f"Could not read image dimensions for {png_path}")
    w, h = int(dims[0]), int(dims[1])
    if w < 299 or h < 299:
        fail(f"Captured image too small: {w}x{h}")

    raw = subprocess.run(["convert", png_path, "-depth", "8", "rgb:-"], capture_output=True).stdout
    if len(raw) < w * h * 3:
        fail(f"Raw pixel dump too short: {len(raw)} bytes for {w}x{h} image")

    def pixel(x, y):
        if x < 0 or x >= w or y < 0 or y >= h:
            return (0, 0, 0)
        i = (y * w + x) * 3
        return (raw[i], raw[i+1], raw[i+2])

    def is_bright(rgb):
        return rgb[0] > 150 and rgb[1] > 150 and rgb[2] > 150

    expected = expected_line_pixels(t)
    hit = 0
    for (x, y) in expected:
        if is_bright(pixel(x, y)):
            hit += 1
    frac = hit / len(expected) if expected else 0

    # Also check the image isn't just fully white (sanity against a "fill everything" cheat).
    total_bright = 0
    sample_n = 0
    for yy in range(0, h, 7):
        for xx in range(0, w, 7):
            sample_n += 1
            if is_bright(pixel(xx, yy)):
                total_bright += 1
    bright_frac = total_bright / sample_n if sample_n else 0

    if frac < 0.80:
        fail(f"t={t}: only {frac*100:.1f}% of expected line pixels ({len(expected)} total) were bright. Image may be wrong/blank.")

    if bright_frac > 0.35:
        fail(f"t={t}: {bright_frac*100:.1f}% of sampled pixels are bright — looks like a filled window, not thin lines.")

    print(f"t={t}: OK, {frac*100:.1f}% of {len(expected)} expected line pixels matched, {bright_frac*100:.1f}% of sampled pixels bright overall (thin lines, not filled).")
    sys.exit(0)

if __name__ == "__main__":
    main()
