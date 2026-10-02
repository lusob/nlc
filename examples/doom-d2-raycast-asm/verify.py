#!/usr/bin/env python3
import sys, subprocess

SINE = [0,3,6,9,12,16,19,22,25,28,31,34,37,40,43,46,49,51,54,57,60,63,65,68,71,73,76,78,81,83,85,88,90,92,94,96,98,100,102,104,106,107,109,111,112,113,115,116,117,118,120,121,122,122,123,124,125,125,126,126,126,127,127,127,127,127,127,127,126,126,126,125,125,124,123,122,122,121,120,118,117,116,115,113,112,111,109,107,106,104,102,100,98,96,94,92,90,88,85,83,81,78,76,73,71,68,65,63,60,57,54,51,49,46,43,40,37,34,31,28,25,22,19,16,12,9,6,3,0,-3,-6,-9,-12,-16,-19,-22,-25,-28,-31,-34,-37,-40,-43,-46,-49,-51,-54,-57,-60,-63,-65,-68,-71,-73,-76,-78,-81,-83,-85,-88,-90,-92,-94,-96,-98,-100,-102,-104,-106,-107,-109,-111,-112,-113,-115,-116,-117,-118,-120,-121,-122,-122,-123,-124,-125,-125,-126,-126,-126,-127,-127,-127,-127,-127,-127,-127,-126,-126,-126,-125,-125,-124,-123,-122,-122,-121,-120,-118,-117,-116,-115,-113,-112,-111,-109,-107,-106,-104,-102,-100,-98,-96,-94,-92,-90,-88,-85,-83,-81,-78,-76,-73,-71,-68,-65,-63,-60,-57,-54,-51,-49,-46,-43,-40,-37,-34,-31,-28,-25,-22,-19,-16,-12,-9,-6,-3]

MAP = [
    "11111111","10000001","10110101","10100001",
    "10001101","10101001","10000101","11111111",
]
def cell(cx, cy):
    if cx < 0 or cx >= 8 or cy < 0 or cy >= 8:
        return 1
    return int(MAP[cy][cx])

SCREEN_W, SCREEN_H = 300, 200
FOV_UNITS = 43
STEP_FX = 8
MAX_STEPS = 400
PROJ = SCREEN_H * 256

def asr(v, n): return v >> n

def compute_wall(i, px_fx, py_fx, player_angle):
    angle = (player_angle - FOV_UNITS//2 + (i*FOV_UNITS)//SCREEN_W) & 255
    cosv, sinv = SINE[(angle+64)&255], SINE[angle]
    dist_fx = 0
    hit = False
    for _ in range(MAX_STEPS):
        dist_fx += STEP_FX
        test_x = px_fx + asr(dist_fx*cosv, 7)
        test_y = py_fx + asr(dist_fx*sinv, 7)
        cx, cy = test_x >> 8, test_y >> 8
        if cell(cx, cy) == 1:
            hit = True
            break
    if not hit:
        dist_fx = MAX_STEPS * STEP_FX
    wall_h = PROJ // dist_fx if dist_fx > 0 else SCREEN_H
    if wall_h > SCREEN_H:
        wall_h = SCREEN_H
    top = (SCREEN_H - wall_h) // 2
    bottom = top + wall_h
    return top, bottom

def fail(msg):
    print(msg)
    sys.exit(1)

def main():
    png_path = sys.argv[1]
    dims = subprocess.run(["identify","-format","%w %h",png_path], capture_output=True, text=True).stdout.split()
    w, h = int(dims[0]), int(dims[1])
    if w < 299 or h < 199:
        fail(f"image too small: {w}x{h}")
    raw = subprocess.run(["convert",png_path,"-depth","8","rgb:-"], capture_output=True).stdout

    def px(x, y):
        i = (y*w+x)*3
        if i+2 >= len(raw): return (0,0,0)
        return (raw[i], raw[i+1], raw[i+2])

    def classify(rgb):
        r,g,b = rgb
        # ceiling ~ (48,48,80), floor ~ (80,64,48), wall ~ (144,144,144)
        if abs(r-48)<25 and abs(g-48)<25 and abs(b-80)<25: return "ceiling"
        if abs(r-80)<25 and abs(g-64)<25 and abs(b-48)<25: return "floor"
        if abs(r-144)<25 and abs(g-144)<25 and abs(b-144)<25: return "wall"
        return None

    px_fx, py_fx, angle = 896, 384, 0
    checked = 0
    matched = 0
    for i in range(5, SCREEN_W, 15):
        top, bottom = compute_wall(i, px_fx, py_fx, angle)
        mid = (top+bottom)//2
        # sample 3 points: well above the wall (ceiling, if top>10), wall middle, well below (floor, if bottom<190)
        pts = []
        if top > 12: pts.append((top-8, "ceiling"))
        pts.append((mid, "wall"))
        if bottom < 188: pts.append((bottom+8, "floor"))
        for (y, expected) in pts:
            checked += 1
            actual = classify(px(i, y))
            if actual == expected:
                matched += 1

    frac = matched/checked if checked else 0
    if frac < 0.85:
        fail(f"Only {matched}/{checked} ({frac*100:.1f}%) sampled points matched the expected ceiling/wall/floor layout.")

    print(f"OK: {matched}/{checked} ({frac*100:.1f}%) sampled points matched the expected raycast silhouette.")
    sys.exit(0)

if __name__ == "__main__":
    main()
