#!/usr/bin/env python3
import sys, subprocess

# Pure candidate colors we expect to see (plus black for background/edges).
CANDIDATES = {
    "red":     (255, 0, 0),
    "cyan":    (0, 255, 255),
    "green":   (0, 255, 0),
    "magenta": (255, 0, 255),
    "blue":    (0, 0, 255),
    "yellow":  (255, 255, 0),
}

def classify(rgb, tol=40):
    r, g, b = rgb
    if r < tol and g < tol and b < tol:
        return "black"
    for name, (cr, cg, cb) in CANDIDATES.items():
        if abs(r - cr) < tol and abs(g - cg) < tol and abs(b - cb) < tol:
            return name
    return None  # anti-aliasing edge / unknown, ignored

def load_image(png_path):
    dims = subprocess.run(["identify", "-format", "%w %h", png_path], capture_output=True, text=True).stdout.split()
    w, h = int(dims[0]), int(dims[1])
    raw = subprocess.run(["convert", png_path, "-depth", "8", "rgb:-"], capture_output=True).stdout
    return raw, w, h

def color_histogram(raw, w, h, step=2):
    counts = {}
    total = 0
    for y in range(0, h, step):
        for x in range(0, w, step):
            i = (y * w + x) * 3
            if i + 2 >= len(raw):
                continue
            c = classify((raw[i], raw[i+1], raw[i+2]))
            if c is None:
                continue
            counts[c] = counts.get(c, 0) + 1
            total += 1
    return counts, total

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])

    raw, w, h = load_image(png_path)
    if w < 299 or h < 299:
        fail(f"t={t}: captured image too small: {w}x{h}")

    counts, total = color_histogram(raw, w, h)
    non_black = {k: v for k, v in counts.items() if k != "black"}
    non_black_frac = sum(non_black.values()) / total if total else 0
    distinct_faces = len(non_black)

    if distinct_faces < 2:
        fail(f"t={t}: only {distinct_faces} distinct face color(s) found ({non_black}) — expected at least 2 visible faces. Full histogram: {counts}")

    if non_black_frac < 0.20:
        fail(f"t={t}: only {non_black_frac*100:.1f}% of sampled pixels are a face color — doesn't look filled. Histogram: {counts}")

    if non_black_frac > 0.85:
        fail(f"t={t}: {non_black_frac*100:.1f}% of pixels are colored, almost nothing is black — window edges/background missing?")

    print(f"t={t}: OK, {distinct_faces} face colors visible ({sorted(non_black.keys())}), {non_black_frac*100:.1f}% of window filled. Histogram: {counts}")
    return counts

if __name__ == "__main__":
    result = main()
