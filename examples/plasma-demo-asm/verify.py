#!/usr/bin/env python3
import sys

RAMP = " .:-=+*#%@X$&8BW"
RAMP_SET = set(RAMP)
COLS = 60
ROWS = 20

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()

    # Strip the one-time clear-screen sequence if present.
    data = data.replace(b"\x1b[2J", b"", 1)

    frames_raw = data.split(b"\x1b[H")
    frames_raw = [fr for fr in frames_raw if fr.strip(b"\n") != b""]

    if len(frames_raw) < 10:
        fail(f"Only found {len(frames_raw)} usable frames (need at least 10). Raw output length: {len(data)} bytes.")

    parsed_frames = []
    bad = 0
    for i, fr in enumerate(frames_raw):
        try:
            text = fr.decode("ascii")
        except UnicodeDecodeError:
            bad += 1
            continue
        lines = text.split("\n")
        lines = [l for l in lines if l != ""]
        if len(lines) != ROWS:
            bad += 1
            continue
        ok = True
        for l in lines:
            if len(l) != COLS:
                ok = False
                break
            if not all(c in RAMP_SET for c in l):
                ok = False
                break
        if not ok:
            bad += 1
            continue
        parsed_frames.append(lines)

    if len(parsed_frames) < 8:
        fail(f"Only {len(parsed_frames)}/{len(frames_raw)} frames had correct format ({ROWS} lines x {COLS} chars, ramp-only chars). {bad} malformed.")

    # Motion check: at least two frames must differ from each other.
    first = parsed_frames[0]
    any_diff = any(f != first for f in parsed_frames[1:])
    if not any_diff:
        fail("All frames are identical — this is a static image, not an animation.")

    # Sanity: not complete noise either — check adjacent frames are similar-ish
    # (plasma should shift smoothly, not be totally random each frame).
    # Compare frame 0 and frame 1: count differing characters.
    f0 = "".join(parsed_frames[0])
    f1 = "".join(parsed_frames[1])
    diff_count = sum(1 for a, b in zip(f0, f1) if a != b)
    total = len(f0)
    frac = diff_count / total
    if frac > 0.9:
        fail(f"Frame 0 -> Frame 1 changed {frac*100:.0f}% of characters — looks like noise, not a smooth animation shift.")

    print(f"OK: {len(parsed_frames)} well-formed frames, motion detected, frame-to-frame change {frac*100:.0f}% (looks like smooth animation).")
    sys.exit(0)

if __name__ == "__main__":
    main()
