import sys

PIECE_ROT = [240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547]
PIECE_ORDER = ['I','O','T','S','Z','J','L']
COLOR = {'I':1,'O':2,'T':3,'S':4,'Z':5,'J':6,'L':7}

BOARD_W, BOARD_H = 10, 20

def piece_bits(ptype, rot):
    return PIECE_ROT[ptype*4 + rot]

def cells(ptype, rot, px, py):
    bits = piece_bits(ptype, rot)
    out = []
    for i in range(16):
        if bits & (1<<i):
            row, col = i//4, i%4
            out.append((px+col, py+row))
    return out

def collide(board, ptype, rot, px, py):
    for (x,y) in cells(ptype, rot, px, py):
        if x < 0 or x >= BOARD_W or y >= BOARD_H:
            return True
        if y >= 0 and board[y][x] != 0:
            return True
    return False

def lock(board, ptype, rot, px, py):
    color = ptype+1
    for (x,y) in cells(ptype, rot, px, py):
        if 0 <= y < BOARD_H:
            board[y][x] = color

def clear_lines(board):
    new_board = [row for row in board if any(c==0 for c in row)]
    cleared = BOARD_H - len(new_board)
    for _ in range(cleared):
        new_board.insert(0, [0]*BOARD_W)
    return new_board, cleared

def lcg_seq(seed, n):
    vals = []
    for _ in range(n):
        seed = (seed*1103515245+12345) & 0xFFFFFFFF
        vals.append((seed>>16) % 7)
    return vals, seed

def run(seed=42, frames=400, gravity=15, moves=None):
    moves = moves or {}
    board = [[0]*BOARD_W for _ in range(BOARD_H)]
    seed_state = seed
    def next_piece():
        nonlocal seed_state
        seed_state = (seed_state*1103515245+12345) & 0xFFFFFFFF
        return (seed_state>>16) % 7

    ptype = next_piece(); rot=0; px=3; py=0
    if collide(board, ptype, rot, px, py):
        print("game over at spawn (shouldn't happen on empty board)")
        return
    total_cleared = 0
    grav_timer = 0
    for t in range(frames):
        if t in moves:
            action = moves[t]
            if action == 'left' and not collide(board, ptype, rot, px-1, py): px -= 1
            elif action == 'right' and not collide(board, ptype, rot, px+1, py): px += 1
            elif action == 'rotate':
                nr = (rot+1)%4
                if not collide(board, ptype, nr, px, py): rot = nr
            elif action == 'down' and not collide(board, ptype, rot, px, py+1): py += 1

        grav_timer += 1
        if grav_timer >= gravity:
            grav_timer = 0
            if not collide(board, ptype, rot, px, py+1):
                py += 1
            else:
                lock(board, ptype, rot, px, py)
                board, cleared = clear_lines(board)
                total_cleared += cleared
                ptype = next_piece(); rot=0; px=3; py=0
                if collide(board, ptype, rot, px, py):
                    print(f"GAME OVER at t={t}, lines cleared={total_cleared}")
                    return board, total_cleared
    return board, total_cleared

def render(board, ptype=None, rot=None, px=None, py=None):
    disp = [row[:] for row in board]
    if ptype is not None:
        for (x,y) in cells(ptype, rot, px, py):
            if 0<=y<BOARD_H and 0<=x<BOARD_W:
                disp[y][x] = ptype+1
    chars = ' IOTSZJL'
    for row in disp:
        print(''.join(chars[c] for c in row))

if __name__ == "__main__":
    board, cleared = run(seed=42, frames=2000, gravity=10)
    print(f"total lines cleared: {cleared}")
    render(board)
