#!/usr/bin/env python3
import sys, subprocess

def load(png_path):
    dims = subprocess.run(["identify", "-format", "%w %h", png_path], capture_output=True, text=True).stdout.split()
    w, h = int(dims[0]), int(dims[1])
    raw = subprocess.run(["convert", png_path, "-depth", "8", "rgb:-"], capture_output=True).stdout
    return raw, w, h

def brightness(raw, w, h, x, y):
    i = (y * w + x) * 3
    if i + 2 >= len(raw):
        return 0
    return raw[i] + raw[i+1] + raw[i+2]  # 0..765

def fail(msg):
    print(msg)
    sys.exit(1)

def summarize(png_path, t):
    raw, w, h = load(png_path)
    if w < 99 or h < 49:
        fail(f"t={t}: image too small: {w}x{h}")

    top_band = [brightness(raw, w, h, x, y) for y in range(0, h//4) for x in range(0, w, 2)]
    bottom_band = [brightness(raw, w, h, x, y) for y in range(h - h//4, h) for x in range(0, w, 2)]
    mid_band = [brightness(raw, w, h, x, y) for y in range(h//2 - h//8, h//2 + h//8) for x in range(0, w, 2)]

    top_avg = sum(top_band) / len(top_band)
    mid_avg = sum(mid_band) / len(mid_band)
    bottom_avg = sum(bottom_band) / len(bottom_band)

    distinct_levels = len(set(brightness(raw, w, h, x, y) // 40 for y in range(0, h, 2) for x in range(0, w, 2)))

    print(f"t={t}: top_avg={top_avg:.1f} mid_avg={mid_avg:.1f} bottom_avg={bottom_avg:.1f} distinct_brightness_buckets={distinct_levels}")
    return top_avg, mid_avg, bottom_avg, distinct_levels, raw, w, h

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])
    top_avg, mid_avg, bottom_avg, distinct_levels, raw, w, h = summarize(png_path, t)

    # Fire must be much hotter at the bottom than the top (gradient), and have some gradation in the middle too.
    if bottom_avg < top_avg + 150:
        fail(f"t={t}: bottom isn't clearly hotter than top (bottom_avg={bottom_avg:.1f}, top_avg={top_avg:.1f}) — doesn't look like fire rising from the bottom.")

    if bottom_avg < 200:
        fail(f"t={t}: bottom row average brightness only {bottom_avg:.1f} — the fire source doesn't look hot/bright enough.")

    if distinct_levels < 4:
        fail(f"t={t}: only {distinct_levels} distinct brightness levels — looks flat/binary, not a smooth heat gradient.")

    print(f"t={t}: OK — clear bottom-hot/top-cool gradient, {distinct_levels} brightness levels present.")
    return (bottom_avg, top_avg)

if __name__ == "__main__":
    main()
