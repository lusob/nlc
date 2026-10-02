#!/usr/bin/env python3
import sys, subprocess

PIECE_ROT = [240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547]
BOARD_W, BOARD_H = 10, 20
GRAVITY = 6
CELL = 15

COLORS = {0:(0,0,0), 1:(0,255,255), 2:(255,255,0), 3:(128,0,128), 4:(0,255,0), 5:(255,0,0), 6:(0,0,255), 7:(255,128,0)}

def piece_bits(pt, rot): return PIECE_ROT[pt*4+rot]
def cells(pt, rot, px, py):
    bits = piece_bits(pt, rot)
    return [(px+i%4, py+i//4) for i in range(16) if bits&(1<<i)]
def collide(board, pt, rot, px, py):
    for x,y in cells(pt,rot,px,py):
        if x<0 or x>=BOARD_W or y>=BOARD_H: return True
        if y>=0 and board[y][x]!=0: return True
    return False
def lock(board, pt, rot, px, py):
    for x,y in cells(pt,rot,px,py):
        if 0<=y<BOARD_H: board[y][x]=pt+1
def clear_lines(board):
    write_row = BOARD_H-1
    board = [row[:] for row in board]
    for read_row in range(BOARD_H-1,-1,-1):
        if not all(c!=0 for c in board[read_row]):
            if write_row!=read_row: board[write_row]=board[read_row][:]
            write_row -= 1
    for row in range(write_row,-1,-1): board[row]=[0]*BOARD_W
    return board

class Sim:
    def __init__(self, seed=12345):
        self.seed = seed
        self.board = [[0]*BOARD_W for _ in range(BOARD_H)]
        self.grav_timer = 0
        self.pt = self._next_piece(); self.rot=0; self.px=3; self.py=0
        self.game_over = False
    def _next_piece(self):
        self.seed = (self.seed*1103515245+12345)&0xFFFFFFFF
        return (self.seed>>16)%7
    def step(self, action=None):
        if self.game_over: return
        if action=='left' and not collide(self.board,self.pt,self.rot,self.px-1,self.py): self.px-=1
        elif action=='right' and not collide(self.board,self.pt,self.rot,self.px+1,self.py): self.px+=1
        elif action=='rotate':
            nr=(self.rot+1)%4
            if not collide(self.board,self.pt,nr,self.px,self.py): self.rot=nr
        elif action=='down' and not collide(self.board,self.pt,self.rot,self.px,self.py+1): self.py+=1
        self.grav_timer += 1
        if self.grav_timer >= GRAVITY:
            self.grav_timer = 0
            if not collide(self.board,self.pt,self.rot,self.px,self.py+1):
                self.py += 1
            else:
                lock(self.board,self.pt,self.rot,self.px,self.py)
                self.board = clear_lines(self.board)
                self.pt=self._next_piece(); self.rot=0; self.px=3; self.py=0
                if collide(self.board,self.pt,self.rot,self.px,self.py):
                    self.game_over = True

def run(moves, total_frames):
    sim = Sim()
    snaps = {}
    for t in range(total_frames):
        sim.step(moves.get(t))
        snaps[t] = (sim.pt, sim.rot, sim.px, sim.py, [row[:] for row in sim.board], sim.game_over)
    return snaps

def expected_grid(pt,rot,px,py,board,game_over):
    disp = [row[:] for row in board]
    if not game_over:
        for x,y in cells(pt,rot,px,py):
            if 0<=y<BOARD_H and 0<=x<BOARD_W: disp[y][x]=pt+1
    return disp

def load(png_path):
    dims = subprocess.run(["identify","-format","%w %h",png_path], capture_output=True, text=True).stdout.split()
    w,h = int(dims[0]), int(dims[1])
    raw = subprocess.run(["convert",png_path,"-depth","8","rgb:-"], capture_output=True).stdout
    return raw,w,h

def px(raw,w,h,x,y):
    i=(y*w+x)*3
    if i+2>=len(raw): return (0,0,0)
    return (raw[i],raw[i+1],raw[i+2])

def fail(msg):
    print(msg); sys.exit(1)

def check(png_path, disp, label):
    raw,w,h = load(png_path)
    if w < 149 or h < 299:
        fail(f"{label}: image too small {w}x{h}")
    checked=0; matched=0
    for row in range(BOARD_H):
        for col in range(BOARD_W):
            expected_color = COLORS[disp[row][col]]
            cx, cy = col*CELL+7, row*CELL+7
            actual = px(raw,w,h,cx,cy)
            checked += 1
            if all(abs(actual[i]-expected_color[i])<30 for i in range(3)):
                matched += 1
    frac = matched/checked
    if frac < 0.97:
        fail(f"{label}: only {matched}/{checked} ({frac*100:.1f}%) cells matched expected board state.")
    print(f"{label}: OK, {matched}/{checked} ({frac*100:.1f}%) cells matched.")

def main():
    png_path = sys.argv[1]
    t = int(sys.argv[2])
    moves = {5: 'right', 12: 'rotate'}
    snaps = run(moves, max(t+1, 200))
    pt,rot,px_,py_,board,go = snaps[t]
    disp = expected_grid(pt,rot,px_,py_,board,go)
    check(png_path, disp, f"t={t}")

if __name__ == "__main__":
    main()
