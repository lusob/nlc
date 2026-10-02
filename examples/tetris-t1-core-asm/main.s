    .equ S_SEED, 0
    .equ S_TYPE, 4
    .equ S_ROT, 8
    .equ S_PX, 12
    .equ S_PY, 16
    .equ S_GT, 20
    .equ S_GO, 24
    .equ S_COL, 28
    .equ S_PC, 60

    .data
    .balign 4
state:
    .word 12345
    .word 0
    .word 0
    .word 3
    .word 0
    .word 0
    .word 0
    .word 0x00000000, 0x0000FFFF, 0x00FFFF00, 0x00800080, 0x0000FF00, 0x00FF0000, 0x000000FF, 0x00FF8000
    .hword 240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547
saddr:
    .hword 1
    .ascii "/tmp/.X11-unix/X0"
    .zero 91
setup:
    .byte 0x6c, 0
    .hword 11, 0, 18, 16, 0
    .ascii "MIT-MAGIC-COOKIE-1"
    .zero 2
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
m_wid:   .ascii "window_id=0x"
m_press: .ascii "press "
m_rel:   .ascii "release "
m_frame: .ascii "frame="

    .bss
    .balign 8
rbuf:   .skip 32768
req:    .skip 2048
evbuf:  .skip 32
tspec:  .skip 16
numbuf: .skip 32
board:  .skip 200

    .text
    .global _start

xwrite:
    mov w0, w19
    mov x8, #64
    svc #0
    ret

print:
    mov x0, #1
    mov x8, #64
    svc #0
    ret

read_n:
    mov w0, w19
    mov x8, #63
    svc #0
    cmp x0, #1
    b.lt fail
    add x1, x1, x0
    subs x2, x2, x0
    b.gt read_n
    ret

dosleep:
    adrp x0, tspec
    add x0, x0, :lo12:tspec
    str xzr, [x0]
    str x2, [x0, #8]
    mov x1, #0
    mov x8, #101
    svc #0
    ret

pdec:
    stp x29, x30, [sp, #-16]!
    adrp x1, numbuf
    add x1, x1, :lo12:numbuf
    add x1, x1, #30
    mov w4, #10
    strb w4, [x1]
    mov x2, #1
    mov w3, #10
1:  udiv w4, w0, w3
    msub w5, w4, w3, w0
    add w5, w5, #48
    sub x1, x1, #1
    strb w5, [x1]
    add x2, x2, #1
    mov w0, w4
    cbnz w0, 1b
    bl print
    ldp x29, x30, [sp], #16
    ret

hex8:
    stp x29, x30, [sp, #-16]!
    adrp x1, numbuf
    add x1, x1, :lo12:numbuf
    mov x6, x1
    mov w2, #8
1:  ror w0, w0, #28
    and w3, w0, #15
    add w3, w3, #48
    cmp w3, #57
    b.le 2f
    add w3, w3, #39
2:  strb w3, [x6], #1
    subs w2, w2, #1
    b.ne 1b
    mov w3, #10
    strb w3, [x6]
    mov x2, #9
    bl print
    ldp x29, x30, [sp], #16
    ret

lcg:
    ldr w0, [x27, #S_SEED]
    movz w1, #0x4E6D
    movk w1, #0x41C6, lsl #16
    mul w0, w0, w1
    mov w1, #12345
    add w0, w0, w1
    str w0, [x27, #S_SEED]
    lsr w0, w0, #16
    mov w1, #7
    udiv w2, w0, w1
    msub w0, w2, w1, w0
    ret

pbits:
    add w9, w1, w0, lsl #2
    add x9, x27, w9, uxtw #1
    ldrh w0, [x9, #S_PC]
    ret

collide:
    stp x29, x30, [sp, #-16]!
    bl pbits
    mov w4, #0
1:  lsr w5, w0, w4
    tbz w5, #0, 3f
    and w6, w4, #3
    add w6, w6, w2
    lsr w7, w4, #2
    add w7, w7, w3
    cmp w6, #10
    b.hs 5f
    cmp w7, #20
    b.ge 5f
    tbnz w7, #31, 3f
    mov w9, #10
    madd w9, w7, w9, w6
    ldrb w9, [x28, w9, uxtw]
    cbnz w9, 5f
3:  add w4, w4, #1
    cmp w4, #16
    b.lt 1b
    mov w0, #0
    b 6f
5:  mov w0, #1
6:  ldp x29, x30, [sp], #16
    ret

addrect:
    mov w9, #15
    mul w0, w0, w9
    mul w1, w1, w9
    strh w0, [x2], #2
    strh w1, [x2], #2
    strh w9, [x2], #2
    strh w9, [x2], #2
    ret

flush:
    adrp x1, req
    add x1, x1, :lo12:req
    sub x3, x2, x1
    sub x3, x3, #12
    cbz x3, 1f
    mov w4, #70
    strb w4, [x1]
    strb wzr, [x1, #1]
    lsr w4, w3, #2
    add w4, w4, #3
    strh w4, [x1, #2]
    str w24, [x1, #4]
    str w0, [x1, #8]
    add x2, x3, #12
    stp x29, x30, [sp, #-16]!
    bl xwrite
    ldp x29, x30, [sp], #16
1:  ret

fail:
    mov x0, #1
    mov x8, #94
    svc #0

_start:
    adrp x27, state
    add x27, x27, :lo12:state
    mov x0, #1
    mov x1, #1
    mov x2, #0
    mov x8, #198
    svc #0
    mov w19, w0
    adrp x1, saddr
    add x1, x1, :lo12:saddr
    mov x2, #110
    mov x8, #203
    svc #0
    tbnz x0, #63, fail
    adrp x1, setup
    add x1, x1, :lo12:setup
    mov x2, #48
    bl xwrite
    adrp x28, rbuf
    add x28, x28, :lo12:rbuf
    mov x1, x28
    mov x2, #8
    bl read_n
    ldrh w2, [x28, #6]
    lsl w2, w2, #2
    add x1, x28, #8
    bl read_n
    ldrb w0, [x28]
    cmp w0, #1
    b.ne fail
    ldr w20, [x28, #12]
    ldrh w0, [x28, #24]
    add w0, w0, #3
    bic w0, w0, #3
    ldrb w1, [x28, #29]
    add w0, w0, w1, lsl #3
    add w0, w0, #40
    add x28, x28, w0, uxtw
    ldr w21, [x28]
    ldr w22, [x28, #32]
    ldrb w23, [x28, #38]
    orr w24, w20, #1
    adrp x1, m_wid
    add x1, x1, :lo12:m_wid
    mov x2, #12
    bl print
    mov w0, w24
    bl hex8
    adrp x28, req
    add x28, x28, :lo12:req
    mov w0, #1
    strb w0, [x28]
    strb w23, [x28, #1]
    mov w0, #9
    strh w0, [x28, #2]
    str w24, [x28, #4]
    str w21, [x28, #8]
    str wzr, [x28, #12]
    mov w0, #150
    strh w0, [x28, #16]
    mov w0, #300
    strh w0, [x28, #18]
    strh wzr, [x28, #20]
    mov w0, #1
    strh w0, [x28, #22]
    str w22, [x28, #24]
    mov w0, #0x800
    str w0, [x28, #28]
    mov w0, #3
    str w0, [x28, #32]
    mov x1, x28
    mov x2, #36
    bl xwrite
    mov w0, #8
    strb w0, [x28]
    strb wzr, [x28, #1]
    mov w0, #2
    strh w0, [x28, #2]
    str w24, [x28, #4]
    mov x1, x28
    mov x2, #8
    bl xwrite
    movz w2, #0xA300
    movk w2, #0x11E1, lsl #16
    bl dosleep
    mov w25, #0
gcloop:
    mov w0, #55
    strb w0, [x28]
    strb wzr, [x28, #1]
    mov w0, #5
    strh w0, [x28, #2]
    add w0, w25, #2
    orr w0, w0, w20
    str w0, [x28, #4]
    str w24, [x28, #8]
    mov w0, #4
    str w0, [x28, #12]
    add x9, x27, w25, uxtw #2
    ldr w0, [x9, #S_COL]
    str w0, [x28, #16]
    mov x1, x28
    mov x2, #20
    bl xwrite
    add w25, w25, #1
    cmp w25, #8
    b.lt gcloop
    mov w0, w19
    mov x1, #4
    mov x2, #0x800
    mov x8, #25
    svc #0
    bl lcg
    str w0, [x27, #S_TYPE]
    adrp x28, board
    add x28, x28, :lo12:board
    mov w25, #0

mainloop:
    mov w26, #0
inloop:
    adrp x1, evbuf
    add x1, x1, :lo12:evbuf
    mov x2, #32
    mov w0, w19
    mov x8, #63
    svc #0
    cmp x0, #0
    b.le indone
    adrp x1, evbuf
    add x1, x1, :lo12:evbuf
    ldrb w0, [x1]
    ldrb w23, [x1, #1]
    and w0, w0, #0x7f
    cmp w0, #2
    b.eq kpress
    cmp w0, #3
    b.ne inloop
    adrp x1, m_rel
    add x1, x1, :lo12:m_rel
    mov x2, #8
    bl print
    mov w0, w23
    bl pdec
    b inloop
kpress:
    adrp x1, m_press
    add x1, x1, :lo12:m_press
    mov x2, #6
    bl print
    mov w0, w23
    bl pdec
    cmp w23, #38
    b.ne 1f
    mov w26, #1
    b inloop
1:  cmp w23, #40
    b.ne 2f
    mov w26, #2
    b inloop
2:  cmp w23, #39
    b.ne 3f
    mov w26, #3
    b inloop
3:  cmp w23, #25
    b.ne inloop
    mov w26, #4
    b inloop
indone:
    ldrb w9, [x27, #S_GO]
    cbnz w9, render
    cbz w26, grav
    ldr w0, [x27, #S_TYPE]
    ldr w1, [x27, #S_ROT]
    ldr w2, [x27, #S_PX]
    ldr w3, [x27, #S_PY]
    cmp w26, #1
    b.ne 1f
    sub w2, w2, #1
    bl collide
    cbnz w0, grav
    str w2, [x27, #S_PX]
    b grav
1:  cmp w26, #2
    b.ne 2f
    add w2, w2, #1
    bl collide
    cbnz w0, grav
    str w2, [x27, #S_PX]
    b grav
2:  cmp w26, #3
    b.ne 3f
    add w3, w3, #1
    bl collide
    cbnz w0, grav
    str w3, [x27, #S_PY]
    b grav
3:  add w1, w1, #1
    and w1, w1, #3
    bl collide
    cbnz w0, grav
    str w1, [x27, #S_ROT]
grav:
    ldr w9, [x27, #S_GT]
    add w9, w9, #1
    cmp w9, #6
    b.ge 1f
    str w9, [x27, #S_GT]
    b render
1:  str wzr, [x27, #S_GT]
    ldr w0, [x27, #S_TYPE]
    ldr w1, [x27, #S_ROT]
    ldr w2, [x27, #S_PX]
    ldr w3, [x27, #S_PY]
    add w3, w3, #1
    bl collide
    cbnz w0, lock
    str w3, [x27, #S_PY]
    b render
lock:
    ldr w0, [x27, #S_TYPE]
    ldr w1, [x27, #S_ROT]
    bl pbits
    ldr w2, [x27, #S_PX]
    ldr w3, [x27, #S_PY]
    ldr w4, [x27, #S_TYPE]
    add w4, w4, #1
    mov w5, #0
1:  lsr w6, w0, w5
    tbz w6, #0, 2f
    and w6, w5, #3
    add w6, w6, w2
    lsr w7, w5, #2
    add w7, w7, w3
    tbnz w7, #31, 2f
    cmp w7, #20
    b.ge 2f
    mov w9, #10
    madd w9, w7, w9, w6
    strb w4, [x28, w9, uxtw]
2:  add w5, w5, #1
    cmp w5, #16
    b.lt 1b
    mov w0, #19
    mov w1, #19
clr:
    mov w9, #10
    mul w2, w1, w9
    add x2, x28, w2, uxtw
    mov w3, #0
    mov w4, #1
1:  ldrb w5, [x2, w3, uxtw]
    cbnz w5, 2f
    mov w4, #0
    b 3f
2:  add w3, w3, #1
    cmp w3, #10
    b.lt 1b
3:  cbnz w4, 5f
    cmp w0, w1
    b.eq 4f
    mov w9, #10
    mul w6, w0, w9
    add x6, x28, w6, uxtw
    mov w3, #0
6:  ldrb w5, [x2, w3, uxtw]
    strb w5, [x6, w3, uxtw]
    add w3, w3, #1
    cmp w3, #10
    b.lt 6b
4:  sub w0, w0, #1
5:  subs w1, w1, #1
    b.ge clr
zt: tbnz w0, #31, spawn
    mov w9, #10
    mul w2, w0, w9
    add x2, x28, w2, uxtw
    mov w3, #0
1:  strb wzr, [x2, w3, uxtw]
    add w3, w3, #1
    cmp w3, #10
    b.lt 1b
    sub w0, w0, #1
    b zt
spawn:
    bl lcg
    str w0, [x27, #S_TYPE]
    str wzr, [x27, #S_ROT]
    mov w9, #3
    str w9, [x27, #S_PX]
    str wzr, [x27, #S_PY]
    mov w1, #0
    mov w2, #3
    mov w3, #0
    bl collide
    cbz w0, render
    mov w9, #1
    strb w9, [x27, #S_GO]
render:
    adrp x2, req
    add x2, x2, :lo12:req
    add x2, x2, #12
    strh wzr, [x2], #2
    strh wzr, [x2], #2
    mov w0, #150
    strh w0, [x2], #2
    mov w0, #300
    strh w0, [x2], #2
    orr w0, w20, #2
    bl flush
    mov w21, #1
cloop:
    adrp x2, req
    add x2, x2, :lo12:req
    add x2, x2, #12
    mov w22, #0
1:  ldrb w9, [x28, w22, uxtw]
    cmp w9, w21
    b.ne 2f
    mov w9, #10
    udiv w1, w22, w9
    msub w0, w1, w9, w22
    bl addrect
2:  add w22, w22, #1
    cmp w22, #200
    b.lt 1b
    ldrb w9, [x27, #S_GO]
    cbnz w9, cflush
    ldr w9, [x27, #S_TYPE]
    add w9, w9, #1
    cmp w9, w21
    b.ne cflush
    ldr w0, [x27, #S_TYPE]
    ldr w1, [x27, #S_ROT]
    bl pbits
    mov w23, w0
    mov w22, #0
3:  lsr w9, w23, w22
    tbz w9, #0, 4f
    ldr w9, [x27, #S_PX]
    and w0, w22, #3
    add w0, w0, w9
    ldr w9, [x27, #S_PY]
    lsr w1, w22, #2
    add w1, w1, w9
    bl addrect
4:  add w22, w22, #1
    cmp w22, #16
    b.lt 3b
cflush:
    add w0, w21, #2
    orr w0, w0, w20
    bl flush
    add w21, w21, #1
    cmp w21, #8
    b.lt cloop
    adrp x1, m_frame
    add x1, x1, :lo12:m_frame
    mov x2, #6
    bl print
    mov w0, w25
    bl pdec
    movz w2, #0xB400
    movk w2, #0x04C4, lsl #16
    bl dosleep
    add w25, w25, #1
    cmp w25, #1500
    b.lt mainloop
    mov x0, #0
    mov x8, #94
    svc #0
