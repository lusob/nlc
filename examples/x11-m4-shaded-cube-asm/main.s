    .global _start
    .text
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

    // connect(fd, sockaddr_un, 110)
    adrp    x1, sockaddr
    add     x1, x1, :lo12:sockaddr
    mov     x2, #110
    mov     x8, #203
    svc     #0
    cmp     x0, #0
    b.lt    fail

    // write 48-byte setup request
    mov     x0, x19
    adrp    x1, setup_req
    add     x1, x1, :lo12:setup_req
    mov     x2, #48
    mov     x8, #64
    svc     #0

    // read 8-byte reply header
    adrp    x23, rbuf
    add     x23, x23, :lo12:rbuf
    mov     x24, #0
hdr_loop:
    mov     x0, x19
    add     x1, x23, x24
    mov     x2, #8
    sub     x2, x2, x24
    mov     x8, #63
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x24, x24, x0
    cmp     x24, #8
    b.lt    hdr_loop

    ldrb    w0, [x23]
    cmp     w0, #1
    b.ne    fail

    // read addl_len*4 body bytes
    ldrh    w25, [x23, #6]
    lsl     x25, x25, #2
    mov     x24, #0
body_loop:
    cmp     x24, x25
    b.ge    body_done
    mov     x0, x19
    add     x1, x23, #8
    add     x1, x1, x24
    sub     x2, x25, x24
    mov     x8, #63
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x24, x24, x0
    b       body_loop
body_done:
    ldr     w20, [x23, #12]          // resource_id_base
    ldrh    w4, [x23, #24]           // vendor_len
    ldrb    w5, [x23, #29]           // num_formats
    add     w4, w4, #3
    and     w4, w4, #0xfffffffc
    mov     w6, #40
    add     w6, w6, w4
    add     w6, w6, w5, lsl #3
    add     x6, x23, w6, uxtw
    ldr     w26, [x6]                // root_window_id
    ldr     w27, [x6, #32]           // root_visual_id
    ldrb    w28, [x6, #38]           // root_depth

    orr     w21, w20, #1             // window_id

    // print "window_id=0x" + 8 hex digits + newline
    mov     x0, #1
    adrp    x1, widstr
    add     x1, x1, :lo12:widstr
    mov     x2, #12
    mov     x8, #64
    svc     #0
    adrp    x9, numbuf
    add     x9, x9, :lo12:numbuf
    mov     x1, x9
    mov     w4, #28
hex_loop:
    lsr     w5, w21, w4
    and     w5, w5, #15
    add     w5, w5, #48
    cmp     w5, #57
    b.le    1f
    add     w5, w5, #39
1:
    strb    w5, [x1], #1
    subs    w4, w4, #4
    b.ge    hex_loop
    mov     w5, #10
    strb    w5, [x1]
    mov     x0, #1
    mov     x1, x9
    mov     x2, #9
    mov     x8, #64
    svc     #0

    // CreateWindow (opcode 1, 32 bytes)
    adrp    x9, req
    add     x9, x9, :lo12:req
    mov     w0, #1
    strb    w0, [x9]
    strb    w28, [x9, #1]
    mov     w0, #8
    strh    w0, [x9, #2]
    str     w21, [x9, #4]
    str     w26, [x9, #8]
    str     wzr, [x9, #12]
    mov     w0, #300
    strh    w0, [x9, #16]
    strh    w0, [x9, #18]
    strh    wzr, [x9, #20]
    mov     w0, #1
    strh    w0, [x9, #22]
    str     w27, [x9, #24]
    str     wzr, [x9, #28]
    mov     x0, x19
    mov     x1, x9
    mov     x2, #32
    mov     x8, #64
    svc     #0

    // MapWindow (opcode 8, 8 bytes)
    mov     w0, #8
    strb    w0, [x9]
    strb    wzr, [x9, #1]
    mov     w0, #2
    strh    w0, [x9, #2]
    str     w21, [x9, #4]
    mov     x0, x19
    mov     x1, x9
    mov     x2, #8
    mov     x8, #64
    svc     #0

    // sleep 300ms
    adrp    x0, ts300
    add     x0, x0, :lo12:ts300
    mov     x1, #0
    mov     x8, #101
    svc     #0

    // 7 CreateGC (opcode 55, 20 bytes each)
    mov     w24, #0
gc_loop:
    mov     w0, #55
    strb    w0, [x9]
    strb    wzr, [x9, #1]
    mov     w0, #5
    strh    w0, [x9, #2]
    add     w0, w24, #2
    orr     w0, w20, w0
    str     w0, [x9, #4]
    str     w21, [x9, #8]
    mov     w0, #4
    str     w0, [x9, #12]
    adrp    x1, colors
    add     x1, x1, :lo12:colors
    ldr     w0, [x1, w24, uxtw #2]
    str     w0, [x9, #16]
    mov     x0, x19
    mov     x1, x9
    mov     x2, #20
    mov     x8, #64
    svc     #0
    add     w24, w24, #1
    cmp     w24, #7
    b.lt    gc_loop

    mov     w22, #0                  // t
frame_loop:
    // sa, ca, sb, cb
    and     w0, w22, #63
    add     w1, w0, #16
    and     w1, w1, #63
    lsl     w2, w22, #1
    and     w2, w2, #63
    add     w3, w2, #16
    and     w3, w3, #63
    adrp    x4, sine
    add     x4, x4, :lo12:sine
    ldrsb   w5, [x4, w0, uxtw]       // sa
    ldrsb   w6, [x4, w1, uxtw]       // ca
    ldrsb   w7, [x4, w2, uxtw]       // sb
    ldrsb   w10, [x4, w3, uxtw]      // cb

    // rotate + project 8 vertices, keep depth z2
    mov     w11, #0
    adrp    x12, verts
    add     x12, x12, :lo12:verts
    adrp    x13, sxa
    add     x13, x13, :lo12:sxa
    adrp    x14, sya
    add     x14, x14, :lo12:sya
    adrp    x15, depa
    add     x15, x15, :lo12:depa
v_loop:
    mov     w0, #6
    mul     w0, w11, w0
    add     x1, x12, w0, uxtw
    ldrsh   w2, [x1]                 // x
    ldrsh   w3, [x1, #2]             // y
    ldrsh   w4, [x1, #4]             // z
    mul     w16, w3, w6
    msub    w16, w4, w5, w16
    asr     w16, w16, #7             // y1 = (y*ca - z*sa)>>7
    mul     w17, w3, w5
    madd    w17, w4, w6, w17
    asr     w17, w17, #7             // z1 = (y*sa + z*ca)>>7
    mul     w0, w2, w10
    madd    w0, w17, w7, w0
    asr     w0, w0, #7               // x2 = (x*cb + z1*sb)>>7
    mul     w1, w17, w10
    msub    w1, w2, w7, w1
    asr     w1, w1, #7               // z2 = (-x*sb + z1*cb)>>7
    add     w0, w0, #150
    add     w16, w16, #150
    strh    w0, [x13, w11, uxtw #1]
    strh    w16, [x14, w11, uxtw #1]
    str     w1, [x15, w11, uxtw #2]
    add     w11, w11, #1
    cmp     w11, #8
    b.lt    v_loop

    // per-face depth sums + face index list
    adrp    x12, faces
    add     x12, x12, :lo12:faces
    adrp    x13, fdep
    add     x13, x13, :lo12:fdep
    adrp    x14, fidx
    add     x14, x14, :lo12:fidx
    mov     w11, #0
fd_loop:
    add     x1, x12, w11, uxtw #2
    mov     w2, #0
    mov     w3, #0
fd_sum:
    ldrb    w4, [x1, w3, uxtw]
    ldr     w5, [x15, w4, uxtw #2]
    add     w2, w2, w5
    add     w3, w3, #1
    cmp     w3, #4
    b.lt    fd_sum
    str     w2, [x13, w11, uxtw #2]
    strb    w11, [x14, w11, uxtw]
    add     w11, w11, #1
    cmp     w11, #6
    b.lt    fd_loop

    // bubble sort faces ascending by depth
    mov     w11, #0
sort_outer:
    mov     w2, #0
sort_inner:
    ldr     w3, [x13, w2, uxtw #2]
    add     w4, w2, #1
    ldr     w5, [x13, w4, uxtw #2]
    cmp     w3, w5
    b.le    no_swap
    str     w5, [x13, w2, uxtw #2]
    str     w3, [x13, w4, uxtw #2]
    ldrb    w6, [x14, w2, uxtw]
    ldrb    w7, [x14, w4, uxtw]
    strb    w7, [x14, w2, uxtw]
    strb    w6, [x14, w4, uxtw]
no_swap:
    add     w2, w2, #1
    cmp     w2, #5
    b.lt    sort_inner
    add     w11, w11, #1
    cmp     w11, #5
    b.lt    sort_outer

    // clear window: PolyFillRectangle (opcode 70), gc_black
    adrp    x9, req
    add     x9, x9, :lo12:req
    mov     w0, #70
    strb    w0, [x9]
    strb    wzr, [x9, #1]
    mov     w0, #5
    strh    w0, [x9, #2]
    str     w21, [x9, #4]
    orr     w0, w20, #2
    str     w0, [x9, #8]
    str     wzr, [x9, #12]
    mov     w0, #300
    strh    w0, [x9, #16]
    strh    w0, [x9, #18]
    mov     x0, x19
    mov     x1, x9
    mov     x2, #20
    mov     x8, #64
    svc     #0

    // draw 6 faces back-to-front: FillPoly (opcode 69, 32 bytes)
    mov     w24, #0
face_draw:
    ldrb    w25, [x14, w24, uxtw]    // sorted face index
    mov     w0, #69
    strb    w0, [x9]
    strb    wzr, [x9, #1]
    mov     w0, #8
    strh    w0, [x9, #2]
    str     w21, [x9, #4]
    add     w0, w25, #3
    orr     w0, w20, w0              // face's GC
    str     w0, [x9, #8]
    mov     w0, #2
    strb    w0, [x9, #12]            // Convex
    strb    wzr, [x9, #13]           // CoordModeOrigin
    strh    wzr, [x9, #14]
    adrp    x12, faces
    add     x12, x12, :lo12:faces
    add     x12, x12, w25, uxtw #2
    adrp    x1, sxa
    add     x1, x1, :lo12:sxa
    adrp    x2, sya
    add     x2, x2, :lo12:sya
    mov     w3, #0
pt_loop:
    ldrb    w4, [x12, w3, uxtw]
    ldrh    w5, [x1, w4, uxtw #1]
    ldrh    w6, [x2, w4, uxtw #1]
    add     w7, w3, #4
    lsl     w7, w7, #2               // 16 + j*4
    strh    w5, [x9, w7, uxtw]
    add     w7, w7, #2
    strh    w6, [x9, w7, uxtw]
    add     w3, w3, #1
    cmp     w3, #4
    b.lt    pt_loop
    mov     x0, x19
    mov     x1, x9
    mov     x2, #32
    mov     x8, #64
    svc     #0
    add     w24, w24, #1
    cmp     w24, #6
    b.lt    face_draw

    // 12 black edges on top: PolySegment (opcode 66, 108 bytes)
    mov     w0, #66
    strb    w0, [x9]
    strb    wzr, [x9, #1]
    mov     w0, #27
    strh    w0, [x9, #2]
    str     w21, [x9, #4]
    orr     w0, w20, #2
    str     w0, [x9, #8]
    adrp    x12, edges
    add     x12, x12, :lo12:edges
    adrp    x1, sxa
    add     x1, x1, :lo12:sxa
    adrp    x2, sya
    add     x2, x2, :lo12:sya
    mov     w3, #0
seg_loop:
    lsl     w4, w3, #1
    ldrb    w5, [x12, w4, uxtw]
    add     w4, w4, #1
    ldrb    w6, [x12, w4, uxtw]
    lsl     w7, w3, #3
    add     w7, w7, #12
    ldrh    w4, [x1, w5, uxtw #1]
    strh    w4, [x9, w7, uxtw]
    ldrh    w4, [x2, w5, uxtw #1]
    add     w7, w7, #2
    strh    w4, [x9, w7, uxtw]
    ldrh    w4, [x1, w6, uxtw #1]
    add     w7, w7, #2
    strh    w4, [x9, w7, uxtw]
    ldrh    w4, [x2, w6, uxtw #1]
    add     w7, w7, #2
    strh    w4, [x9, w7, uxtw]
    add     w3, w3, #1
    cmp     w3, #12
    b.lt    seg_loop
    mov     x0, x19
    mov     x1, x9
    mov     x2, #108
    mov     x8, #64
    svc     #0

    // print "frame=N\n"
    mov     x0, #1
    adrp    x1, framestr
    add     x1, x1, :lo12:framestr
    mov     x2, #6
    mov     x8, #64
    svc     #0
    adrp    x1, numbuf
    add     x1, x1, :lo12:numbuf
    add     x1, x1, #31
    mov     w4, #10
    strb    w4, [x1]
    mov     w2, w22
    mov     x3, x1
itoa_loop:
    udiv    w5, w2, w4
    msub    w6, w5, w4, w2
    add     w6, w6, #48
    sub     x3, x3, #1
    strb    w6, [x3]
    mov     w2, w5
    cbnz    w2, itoa_loop
    mov     x0, #1
    mov     x1, x3
    adrp    x2, numbuf
    add     x2, x2, :lo12:numbuf
    add     x2, x2, #32
    sub     x2, x2, x3
    mov     x8, #64
    svc     #0

    // sleep 80ms
    adrp    x0, ts80
    add     x0, x0, :lo12:ts80
    mov     x1, #0
    mov     x8, #101
    svc     #0

    add     w22, w22, #1
    cmp     w22, #64
    b.lt    frame_loop

    // sleep 2s, exit_group(0)
    adrp    x0, ts2
    add     x0, x0, :lo12:ts2
    mov     x1, #0
    mov     x8, #101
    svc     #0
    mov     x0, #0
    mov     x8, #94
    svc     #0

fail:
    mov     x0, #1
    mov     x8, #94
    svc     #0

    .data
sockaddr:
    .hword  1
    .ascii  "/tmp/.X11-unix/X0"
    .zero   91

setup_req:
    .byte   0x6c, 0
    .hword  11, 0, 18, 16, 0
    .ascii  "MIT-MAGIC-COOKIE-1"
    .zero   2
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

sine:
    .byte   0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126
    .byte   127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12
    .byte   0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126
    .byte   -127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12

verts:
    .hword  -100,-100,-100,  100,-100,-100,  100,100,-100,  -100,100,-100
    .hword  -100,-100,100,   100,-100,100,   100,100,100,   -100,100,100

faces:
    .byte   0,1,5,4,  3,7,6,2,  4,5,6,7,  1,0,3,2,  0,4,7,3,  5,1,2,6

edges:
    .byte   0,1, 1,2, 2,3, 3,0, 4,5, 5,6, 6,7, 7,4, 0,4, 1,5, 2,6, 3,7

    .p2align 2
colors:
    .word   0x00000000, 0x00FF0000, 0x0000FFFF, 0x0000FF00
    .word   0x00FF00FF, 0x000000FF, 0x00FFFF00

    .p2align 3
ts300:
    .quad   0, 300000000
ts80:
    .quad   0, 80000000
ts2:
    .quad   2, 0

widstr:
    .ascii  "window_id=0x"
framestr:
    .ascii  "frame="

    .bss
rbuf:
    .skip   32768
sxa:
    .skip   16
sya:
    .skip   16
depa:
    .skip   32
fdep:
    .skip   24
fidx:
    .skip   8
req:
    .skip   128
numbuf:
    .skip   34
