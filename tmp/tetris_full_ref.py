PIECE_ROT = [240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547]
BOARD_W, BOARD_H = 10, 20
GRAVITY = 6

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
    cleared = write_row+1
    for row in range(write_row,-1,-1): board[row]=[0]*BOARD_W
    return board, cleared

class Sim:
    def __init__(self, seed=12345):
        self.seed = seed
        self.board = [[0]*BOARD_W for _ in range(BOARD_H)]
        self.grav_timer = 0
        self.pt, self.rot, self.px, self.py = self._next_piece(), 0, 3, 0
        self.game_over = False

    def _next_piece(self):
        self.seed = (self.seed*1103515245+12345)&0xFFFFFFFF
        return (self.seed>>16)%7

    def step(self, action=None):
        if self.game_over: return
        if action == 'left' and not collide(self.board,self.pt,self.rot,self.px-1,self.py): self.px-=1
        elif action == 'right' and not collide(self.board,self.pt,self.rot,self.px+1,self.py): self.px+=1
        elif action == 'rotate':
            nr=(self.rot+1)%4
            if not collide(self.board,self.pt,nr,self.px,self.py): self.rot=nr
        elif action == 'down' and not collide(self.board,self.pt,self.rot,self.px,self.py+1): self.py+=1

        self.grav_timer += 1
        if self.grav_timer >= GRAVITY:
            self.grav_timer = 0
            if not collide(self.board,self.pt,self.rot,self.px,self.py+1):
                self.py += 1
            else:
                lock(self.board,self.pt,self.rot,self.px,self.py)
                self.board, _ = clear_lines(self.board)
                self.pt, self.rot, self.px, self.py = self._next_piece(), 0, 3, 0
                if collide(self.board,self.pt,self.rot,self.px,self.py):
                    self.game_over = True

def run(moves, total_frames):
    sim = Sim()
    snapshots = {}
    for t in range(total_frames):
        sim.step(moves.get(t))
        snapshots[t] = (sim.pt, sim.rot, sim.px, sim.py, [row[:] for row in sim.board], sim.game_over)
    return snapshots

CHARS = ' IOTSZJL'
def render(pt,rot,px,py,board):
    disp = [row[:] for row in board]
    for x,y in cells(pt,rot,px,py):
        if 0<=y<BOARD_H and 0<=x<BOARD_W: disp[y][x]=pt+1
    for row in disp: print(''.join(CHARS[c] for c in row))

if __name__ == "__main__":
    moves = {5: 'right', 12: 'rotate'}
    snaps = run(moves, 150)
    for t in [1, 8, 15, 149]:
        pt,rot,px,py,board,go = snaps[t]
        print(f"=== t={t} pt={pt} rot={rot} px={px} py={py} game_over={go} ===")
        render(pt,rot,px,py,board)
        print()
