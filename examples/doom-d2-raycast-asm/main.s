.text
.global _start

_start:
    // socket(AF_UNIX, SOCK_STREAM, 0)
    mov     x0, #1
    mov     x1, #1
    mov     x2, #0
    mov     x8, #198
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0

    // connect(fd, &sockaddr_un, 110)
    mov     x0, x19
    adrp    x1, sockaddr
    add     x1, x1, :lo12:sockaddr
    mov     x2, #110
    mov     x8, #203
    svc     #0
    cmp     x0, #0
    b.ne    fail

    // send 48-byte setup request
    adrp    x1, setup_req
    add     x1, x1, :lo12:setup_req
    mov     x2, #48
    bl      send_all

    // read 8-byte reply header
    adrp    x24, replybuf
    add     x24, x24, :lo12:replybuf
    mov     x1, x24
    mov     x2, #8
    bl      read_n

    // read addl_len*4 more bytes
    ldrh    w2, [x24, #6]
    lsl     x2, x2, #2
    add     x1, x24, #8
    bl      read_n

    // verify success
    ldrb    w0, [x24]
    cmp     w0, #1
    b.ne    fail

    // parse setup reply
    ldr     w20, [x24, #12]          // resource_id_base
    ldrh    w0, [x24, #24]           // vendor_len
    add     w0, w0, #3
    and     w0, w0, #0xfffffffc
    ldrb    w1, [x24, #29]           // num_formats
    add     w0, w0, #40
    add     w0, w0, w1, lsl #3       // root_offset
    add     x2, x24, w0, uxtw
    ldr     w21, [x2]                // root_window_id
    ldr     w22, [x2, #32]           // root_visual_id
    ldrb    w23, [x2, #38]           // root_depth

    orr     w25, w20, #1             // window_id

    // print "window_id=0xXXXXXXXX\n"
    adrp    x3, widhex
    add     x3, x3, :lo12:widhex
    mov     w4, #28
1:  lsr     w5, w25, w4
    and     w5, w5, #15
    cmp     w5, #10
    add     w6, w5, #'0'
    add     w7, w5, #('a'-10)
    csel    w5, w6, w7, lo
    strb    w5, [x3], #1
    subs    w4, w4, #4
    b.ge    1b
    mov     w5, #'\n'
    strb    w5, [x3]
    mov     x0, #1
    adrp    x1, widmsg
    add     x1, x1, :lo12:widmsg
    mov     x2, #21
    mov     x8, #64
    svc     #0

    adrp    x26, reqbuf
    add     x26, x26, :lo12:reqbuf

    // CreateWindow (opcode 1, 32 bytes)
    mov     w0, #1
    strb    w0, [x26]
    strb    w23, [x26, #1]           // depth
    mov     w0, #8
    strh    w0, [x26, #2]            // length
    str     w25, [x26, #4]           // window_id
    str     w21, [x26, #8]           // parent
    str     wzr, [x26, #12]          // x=0, y=0
    mov     w0, #300
    strh    w0, [x26, #16]           // width
    mov     w0, #200
    strh    w0, [x26, #18]           // height
    strh    wzr, [x26, #20]          // border
    mov     w0, #1
    strh    w0, [x26, #22]           // class InputOutput
    str     w22, [x26, #24]          // visual
    str     wzr, [x26, #28]          // value-mask=0
    mov     x1, x26
    mov     x2, #32
    bl      send_all

    // MapWindow (opcode 8, 8 bytes)
    mov     w0, #8
    strb    w0, [x26]
    strb    wzr, [x26, #1]
    mov     w0, #2
    strh    w0, [x26, #2]
    str     w25, [x26, #4]
    mov     x1, x26
    mov     x2, #8
    bl      send_all

    // nanosleep 300ms
    adrp    x0, ts300
    add     x0, x0, :lo12:ts300
    mov     x1, #0
    mov     x8, #101
    svc     #0

    // three GCs
    orr     w0, w20, #2
    mov     w1, #0x3050
    movk    w1, #0x30, lsl #16       // 0x00303050
    bl      make_gc
    orr     w0, w20, #3
    mov     w1, #0x4030
    movk    w1, #0x50, lsl #16       // 0x00504030
    bl      make_gc
    orr     w0, w20, #4
    mov     w1, #0x9090
    movk    w1, #0x90, lsl #16       // 0x00909090
    bl      make_gc

    // ---- raycast all 300 columns into wall request buffer ----
    adrp    x27, wallreq
    add     x27, x27, :lo12:wallreq
    mov     w0, #70
    strb    w0, [x27]                // PolyFillRectangle
    strb    wzr, [x27, #1]
    mov     w0, #603
    strh    w0, [x27, #2]            // length = 2412/4
    str     w25, [x27, #4]           // drawable = window
    orr     w0, w20, #4
    str     w0, [x27, #8]            // gc_wall

    adrp    x28, sine_table
    add     x28, x28, :lo12:sine_table
    adrp    x6, mapdata
    add     x6, x6, :lo12:mapdata

    mov     w9, #0                   // column i
col_loop:
    mov     w0, #43
    mul     w0, w9, w0
    mov     w1, #300
    udiv    w0, w0, w1               // (i*43)/300
    sub     w0, w0, #21              // player_angle(0) - 21 + ...
    and     w10, w0, #255            // angle
    add     w1, w10, #64
    and     w1, w1, #255
    ldrsb   w11, [x28, w1, uxtw]     // cosv
    ldrsb   w12, [x28, w10, uxtw]    // sinv

    mov     w13, #0                  // dist_fx
    mov     w14, #400                // MAX_STEPS
ray_loop:
    add     w13, w13, #8
    mul     w0, w13, w11
    asr     w0, w0, #7
    add     w0, w0, #896             // test_x
    mul     w1, w13, w12
    asr     w1, w1, #7
    add     w1, w1, #384             // test_y
    asr     w0, w0, #8               // cx
    asr     w1, w1, #8               // cy
    cmp     w0, #8
    b.hs    hit                      // out of bounds (incl. negative) = wall
    cmp     w1, #8
    b.hs    hit
    add     w2, w0, w1, lsl #3
    ldrb    w3, [x6, w2, uxtw]
    cbnz    w3, hit
    subs    w14, w14, #1
    b.ne    ray_loop
    mov     w13, #3200               // fallback: very far
hit:
    mov     w0, #51200               // PROJ
    udiv    w0, w0, w13              // wall_h
    cmp     w0, #200
    mov     w1, #200
    csel    w0, w0, w1, ls           // clamp to SCREEN_H
    sub     w1, w1, w0
    asr     w1, w1, #1               // wall_top
    add     x2, x27, #12
    add     x2, x2, w9, uxtw #3
    strh    w9, [x2]                 // x = i
    strh    w1, [x2, #2]             // y = wall_top
    mov     w3, #1
    strh    w3, [x2, #4]             // width = 1
    strh    w0, [x2, #6]             // height = wall_h
    add     w9, w9, #1
    cmp     w9, #300
    b.lt    col_loop

    // ---- ceiling rect ----
    mov     w0, #70
    strb    w0, [x26]
    strb    wzr, [x26, #1]
    mov     w0, #5
    strh    w0, [x26, #2]
    str     w25, [x26, #4]
    orr     w0, w20, #2
    str     w0, [x26, #8]            // gc_ceiling
    strh    wzr, [x26, #12]          // x=0
    strh    wzr, [x26, #14]          // y=0
    mov     w0, #300
    strh    w0, [x26, #16]
    mov     w0, #100
    strh    w0, [x26, #18]
    mov     x1, x26
    mov     x2, #20
    bl      send_all

    // ---- floor rect ----
    orr     w0, w20, #3
    str     w0, [x26, #8]            // gc_floor
    mov     w0, #100
    strh    w0, [x26, #14]           // y=100
    mov     x1, x26
    mov     x2, #20
    bl      send_all

    // ---- 300 wall columns in one request ----
    mov     x1, x27
    mov     x2, #2412
    bl      send_all

    // print "frame=0\n"
    mov     x0, #1
    adrp    x1, frame_msg
    add     x1, x1, :lo12:frame_msg
    mov     x2, #8
    mov     x8, #64
    svc     #0

    // sleep 3s
    adrp    x0, ts3
    add     x0, x0, :lo12:ts3
    mov     x1, #0
    mov     x8, #101
    svc     #0

    mov     x0, #0
    mov     x8, #94
    svc     #0

// make_gc: w0=gc id, w1=foreground; builds CreateGC in reqbuf and sends
make_gc:
    mov     w2, #55
    strb    w2, [x26]
    strb    wzr, [x26, #1]
    mov     w2, #5
    strh    w2, [x26, #2]
    str     w0, [x26, #4]            // cid
    str     w25, [x26, #8]           // drawable
    mov     w2, #4
    str     w2, [x26, #12]           // mask = GCForeground
    str     w1, [x26, #16]
    mov     x1, x26
    mov     x2, #20
    b       send_all

// send_all: x1=buf, x2=len, fd in x19
send_all:
1:  mov     x0, x19
    mov     x8, #64
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x1, x1, x0
    subs    x2, x2, x0
    b.gt    1b
    ret

// read_n: x1=buf, x2=len, fd in x19
read_n:
    cbz     x2, 2f
1:  mov     x0, x19
    mov     x8, #63
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x1, x1, x0
    subs    x2, x2, x0
    b.gt    1b
2:  ret

fail:
    mov     x0, #1
    mov     x8, #94
    svc     #0

.section .data
.balign 4
setup_req:
    .byte   0x6c, 0
    .hword  11
    .hword  0
    .hword  18
    .hword  16
    .hword  0
    .ascii  "MIT-MAGIC-COOKIE-1"
    .byte   0, 0
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

.balign 2
sockaddr:
    .hword  1
    .ascii  "/tmp/.X11-unix/X0"
    .byte   0
    .zero   90

sine_table:
    .byte   0,3,6,9,12,16,19,22,25,28,31,34,37,40,43,46
    .byte   49,51,54,57,60,63,65,68,71,73,76,78,81,83,85,88
    .byte   90,92,94,96,98,100,102,104,106,107,109,111,112,113,115,116
    .byte   117,118,120,121,122,122,123,124,125,125,126,126,126,127,127,127
    .byte   127,127,127,127,126,126,126,125,125,124,123,122,122,121,120,118
    .byte   117,116,115,113,112,111,109,107,106,104,102,100,98,96,94,92
    .byte   90,88,85,83,81,78,76,73,71,68,65,63,60,57,54,51
    .byte   49,46,43,40,37,34,31,28,25,22,19,16,12,9,6,3
    .byte   0,-3,-6,-9,-12,-16,-19,-22,-25,-28,-31,-34,-37,-40,-43,-46
    .byte   -49,-51,-54,-57,-60,-63,-65,-68,-71,-73,-76,-78,-81,-83,-85,-88
    .byte   -90,-92,-94,-96,-98,-100,-102,-104,-106,-107,-109,-111,-112,-113,-115,-116
    .byte   -117,-118,-120,-121,-122,-122,-123,-124,-125,-125,-126,-126,-126,-127,-127,-127
    .byte   -127,-127,-127,-127,-126,-126,-126,-125,-125,-124,-123,-122,-122,-121,-120,-118
    .byte   -117,-116,-115,-113,-112,-111,-109,-107,-106,-104,-102,-100,-98,-96,-94,-92
    .byte   -90,-88,-85,-83,-81,-78,-76,-73,-71,-68,-65,-63,-60,-57,-54,-51
    .byte   -49,-46,-43,-40,-37,-34,-31,-28,-25,-22,-19,-16,-12,-9,-6,-3

mapdata:
    .byte   1,1,1,1,1,1,1,1
    .byte   1,0,0,0,0,0,0,1
    .byte   1,0,1,1,0,1,0,1
    .byte   1,0,1,0,0,0,0,1
    .byte   1,0,0,0,1,1,0,1
    .byte   1,0,1,0,0,0,0,1
    .byte   1,0,0,0,0,1,0,1
    .byte   1,1,1,1,1,1,1,1

widmsg:
    .ascii  "window_id=0x"
widhex:
    .space  9

frame_msg:
    .ascii  "frame=0\n"

.balign 8
ts300:
    .quad   0
    .quad   300000000
ts3:
    .quad   3
    .quad   0

.section .bss
.balign 8
replybuf:
    .space  8192
reqbuf:
    .space  64
wallreq:
    .space  2412
