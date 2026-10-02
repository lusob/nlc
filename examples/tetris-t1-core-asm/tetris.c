#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <stdlib.h>
#include <stdio.h>

static const uint16_t PIECE_ROT[28] = {240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547};
#define BOARD_W 10
#define BOARD_H 20
#define GRAVITY 6
#define CELL 15

static uint8_t board[BOARD_H][BOARD_W];
static uint32_t rand_seed = 12345;
static int piece_type, piece_rot, piece_x, piece_y;
static int grav_timer = 0, game_over = 0;
static int fd;
static uint32_t window_id, gc_black, gc[8];

static uint32_t lcg(void) {
    rand_seed = rand_seed * 1103515245u + 12345u;
    return (rand_seed >> 16) % 7;
}

static uint16_t piece_bits(int t, int r) { return PIECE_ROT[t*4+r]; }

static int collide(int t, int r, int px, int py) {
    uint16_t bits = piece_bits(t, r);
    for (int i = 0; i < 16; i++) {
        if (!(bits & (1<<i))) continue;
        int x = px + i%4, y = py + i/4;
        if (x < 0 || x >= BOARD_W || y >= BOARD_H) return 1;
        if (y >= 0 && board[y][x] != 0) return 1;
    }
    return 0;
}

static void lock_piece(int t, int r, int px, int py) {
    uint16_t bits = piece_bits(t, r);
    for (int i = 0; i < 16; i++) {
        if (!(bits & (1<<i))) continue;
        int x = px + i%4, y = py + i/4;
        if (y >= 0 && y < BOARD_H) board[y][x] = t+1;
    }
}

static void clear_lines(void) {
    int write_row = BOARD_H - 1;
    for (int read_row = BOARD_H - 1; read_row >= 0; read_row--) {
        int full = 1;
        for (int c = 0; c < BOARD_W; c++) if (board[read_row][c] == 0) { full = 0; break; }
        if (!full) {
            if (write_row != read_row) memcpy(board[write_row], board[read_row], BOARD_W);
            write_row--;
        }
    }
    for (int row = write_row; row >= 0; row--) memset(board[row], 0, BOARD_W);
}

static void send_all(const void *buf, size_t len) { write(fd, buf, len); }

static void create_window(uint32_t wid, uint32_t parent, int w, int h, uint32_t visual, uint8_t depth) {
    uint8_t req[36] = {0};
    req[0]=1; req[1]=depth; *(uint16_t*)(req+2)=9;
    *(uint32_t*)(req+4)=wid; *(uint32_t*)(req+8)=parent;
    *(int16_t*)(req+12)=0; *(int16_t*)(req+14)=0;
    *(uint16_t*)(req+16)=w; *(uint16_t*)(req+18)=h;
    *(uint16_t*)(req+20)=0; *(uint16_t*)(req+22)=1;
    *(uint32_t*)(req+24)=visual; *(uint32_t*)(req+28)=0x800;
    *(uint32_t*)(req+32)=0x3;
    send_all(req, 36);
}
static void map_window(uint32_t wid) {
    uint8_t req[8] = {0}; req[0]=8; *(uint16_t*)(req+2)=2; *(uint32_t*)(req+4)=wid; send_all(req,8);
}
static void make_gc(uint32_t cid, uint32_t drawable, uint32_t color) {
    uint8_t req[20] = {0}; req[0]=55; *(uint16_t*)(req+2)=5;
    *(uint32_t*)(req+4)=cid; *(uint32_t*)(req+8)=drawable;
    *(uint32_t*)(req+12)=0x4; *(uint32_t*)(req+16)=color;
    send_all(req,20);
}
static void fill_rect(uint32_t drawable, uint32_t gcid, int16_t x, int16_t y, uint16_t w, uint16_t h) {
    uint8_t req[20] = {0}; req[0]=70; *(uint16_t*)(req+2)=5;
    *(uint32_t*)(req+4)=drawable; *(uint32_t*)(req+8)=gcid;
    *(int16_t*)(req+12)=x; *(int16_t*)(req+14)=y;
    *(uint16_t*)(req+16)=w; *(uint16_t*)(req+18)=h;
    send_all(req,20);
}
static void fill_rects_many(uint32_t drawable, uint32_t gcid, int16_t *rects, int n) {
    int total = 8 + n*8;
    uint8_t *req = malloc(total);
    memset(req, 0, 8);
    req[0]=70; *(uint16_t*)(req+2)=(uint16_t)(total/4);
    *(uint32_t*)(req+4)=drawable;
    memcpy(req+4, &drawable, 4);
    memcpy(req+8, &gcid, 4);
    memcpy(req+12, rects, n*8);
    send_all(req, total);
    free(req);
}

static void nsleep(long ms) {
    struct timespec ts = {0, ms*1000000L};
    nanosleep(&ts, NULL);
}

int main(void) {
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/tmp/.X11-unix/X0");
    connect(s, (struct sockaddr*)&addr, sizeof(addr));
    fd = s;

    uint8_t cookie[16] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
    uint8_t req[48] = {0};
    req[0]='l'; *(uint16_t*)(req+2)=11; *(uint16_t*)(req+6)=18; *(uint16_t*)(req+8)=16;
    memcpy(req+12, "MIT-MAGIC-COOKIE-1", 18);
    memcpy(req+32, cookie, 16);
    write(fd, req, 48);

    uint8_t hdr[8]; read(fd, hdr, 8);
    uint16_t addl_len = *(uint16_t*)(hdr+6);
    uint8_t *body = malloc(addl_len*4);
    int got = 0;
    while (got < addl_len*4) got += read(fd, body+got, addl_len*4-got);

    uint16_t vendor_len = *(uint16_t*)(body+16);
    uint8_t num_formats = body[21];
    uint32_t resource_id_base = *(uint32_t*)(body+4);
    int vendor_end = 32 + ((vendor_len+3)&~3);
    int root_off = vendor_end + num_formats*8;
    uint32_t root_window = *(uint32_t*)(body+root_off);
    uint32_t root_visual = *(uint32_t*)(body+root_off+32);
    uint8_t root_depth = body[root_off+38];

    window_id = resource_id_base | 1;
    gc_black = resource_id_base | 2;
    for (int i = 1; i <= 7; i++) gc[i] = resource_id_base | (2+i);

    char wbuf[32];
    int n = snprintf(wbuf, sizeof(wbuf), "window_id=0x%08x\n", window_id);
    write(1, wbuf, n);

    create_window(window_id, root_window, 150, 300, root_visual, root_depth);
    map_window(window_id);
    nsleep(300);

    uint32_t colors[8] = {0,0x00FFFF,0xFFFF00,0x800080,0x00FF00,0xFF0000,0x0000FF,0xFF8000};
    make_gc(gc_black, window_id, 0);
    for (int i = 1; i <= 7; i++) make_gc(gc[i], window_id, colors[i]);

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    piece_type = lcg(); piece_rot=0; piece_x=3; piece_y=0;

    for (int t = 0; t < 1500; t++) {
        char action = 0;
        uint8_t evbuf[4096];
        for (;;) {
            int r = read(fd, evbuf, sizeof(evbuf));
            if (r <= 0) break;
            for (int i = 0; i+32 <= r; i += 32) {
                int etype = evbuf[i] & 0x7f;
                int kc = evbuf[i+1];
                if (etype != 2 && etype != 3) continue;
                char pbuf[16];
                int pn = snprintf(pbuf, sizeof(pbuf), "%s %d\n", etype==2?"press":"release", kc);
                write(1, pbuf, pn);
                if (etype == 2) {
                    if (kc==38) action='l';
                    else if (kc==40) action='r';
                    else if (kc==39) action='d';
                    else if (kc==25) action='w';
                }
            }
        }

        if (!game_over) {
            if (action=='l' && !collide(piece_type,piece_rot,piece_x-1,piece_y)) piece_x--;
            else if (action=='r' && !collide(piece_type,piece_rot,piece_x+1,piece_y)) piece_x++;
            else if (action=='d' && !collide(piece_type,piece_rot,piece_x,piece_y+1)) piece_y++;
            else if (action=='w') {
                int nr = (piece_rot+1)&3;
                if (!collide(piece_type,nr,piece_x,piece_y)) piece_rot = nr;
            }
            grav_timer++;
            if (grav_timer >= GRAVITY) {
                grav_timer = 0;
                if (!collide(piece_type,piece_rot,piece_x,piece_y+1)) piece_y++;
                else {
                    lock_piece(piece_type,piece_rot,piece_x,piece_y);
                    clear_lines();
                    piece_type = lcg(); piece_rot=0; piece_x=3; piece_y=0;
                    if (collide(piece_type,piece_rot,piece_x,piece_y)) game_over = 1;
                }
            }
        }

        fill_rect(window_id, gc_black, 0, 0, 150, 300);
        for (int color = 1; color <= 7; color++) {
            int16_t rects[220*4];
            int nrects = 0;
            for (int row = 0; row < BOARD_H; row++)
                for (int col = 0; col < BOARD_W; col++)
                    if (board[row][col] == color) {
                        rects[nrects*4+0]=col*CELL; rects[nrects*4+1]=row*CELL;
                        rects[nrects*4+2]=CELL; rects[nrects*4+3]=CELL;
                        nrects++;
                    }
            if (!game_over && piece_type+1 == color) {
                uint16_t bits = piece_bits(piece_type, piece_rot);
                for (int i = 0; i < 16; i++) {
                    if (!(bits & (1<<i))) continue;
                    int x = piece_x + i%4, y = piece_y + i/4;
                    if (x>=0 && x<BOARD_W && y>=0 && y<BOARD_H) {
                        rects[nrects*4+0]=x*CELL; rects[nrects*4+1]=y*CELL;
                        rects[nrects*4+2]=CELL; rects[nrects*4+3]=CELL;
                        nrects++;
                    }
                }
            }
            if (nrects) fill_rects_many(window_id, gc[color], rects, nrects);
        }

        char fbuf[16];
        int fn = snprintf(fbuf, sizeof(fbuf), "frame=%d\n", t);
        write(1, fbuf, fn);
        nsleep(80);
    }
    return 0;
}
