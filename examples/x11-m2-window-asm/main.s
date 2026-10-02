    .data
    .align 2
sockaddr:
    .hword 1
    .ascii "/tmp/.X11-unix/X0"
    .byte 0
    .space 90                       // total 110 bytes

    .align 2
setup:
    .byte 0x6c, 0
    .hword 11
    .hword 0
    .hword 18
    .hword 16
    .hword 0
    .ascii "MIT-MAGIC-COOKIE-1"
    .byte 0, 0
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

authmsg:
    .ascii "AUTH FAILED\n"
widprefix:
    .ascii "window_id=0x"

    .bss
    .align 3
buf:
    .skip 262160
req:
    .skip 32
line:
    .skip 24

    .text
    .global _start
_start:
    // socket(AF_UNIX, SOCK_STREAM, 0)
    mov     x8, #198
    mov     x0, #1
    mov     x1, #1
    mov     x2, #0
    svc     #0
    tbnz    x0, #63, die1
    mov     x19, x0

    // connect(fd, sockaddr, 110)
    mov     x8, #203
    mov     x0, x19
    adrp    x1, sockaddr
    add     x1, x1, :lo12:sockaddr
    mov     x2, #110
    svc     #0
    cbnz    x0, die1

    // write setup request (48 bytes)
    mov     x8, #64
    mov     x0, x19
    adrp    x1, setup
    add     x1, x1, :lo12:setup
    mov     x2, #48
    svc     #0

    adrp    x20, buf
    add     x20, x20, :lo12:buf

    // read 8-byte reply header
    mov     x21, #0
rdhdr:
    mov     x8, #63
    mov     x0, x19
    add     x1, x20, x21
    mov     x2, #8
    sub     x2, x2, x21
    svc     #0
    cmp     x0, #0
    b.le    die1
    add     x21, x21, x0
    cmp     x21, #8
    b.lt    rdhdr

    // read addl_len*4 more bytes
    ldrh    w22, [x20, #6]
    lsl     x22, x22, #2
    mov     x21, #0
rdbody:
    cmp     x21, x22
    b.ge    rddone
    mov     x8, #63
    mov     x0, x19
    add     x1, x20, #8
    add     x1, x1, x21
    sub     x2, x22, x21
    svc     #0
    cmp     x0, #0
    b.le    die1
    add     x21, x21, x0
    b       rdbody
rddone:
    ldrb    w0, [x20]
    cmp     w0, #1
    b.ne    auth_fail

    // parse handshake
    ldr     w1, [x20, #12]          // resource_id_base
    ldrh    w2, [x20, #24]          // vendor_len
    ldrb    w3, [x20, #29]          // num_formats
    add     w2, w2, #3
    and     w2, w2, #0xfffffffc
    add     w2, w2, #40             // vendor_end
    add     w2, w2, w3, lsl #3      // root_offset
    add     x4, x20, w2, uxtw
    ldr     w23, [x4]               // root window
    ldr     w24, [x4, #32]          // root visual
    ldrb    w25, [x4, #38]          // root depth
    orr     w21, w1, #1             // window_id
    orr     w22, w1, #2             // gc_id

    // build "window_id=0xXXXXXXXX\n"
    adrp    x5, line
    add     x5, x5, :lo12:line
    adrp    x6, widprefix
    add     x6, x6, :lo12:widprefix
    ldr     x7, [x6]
    str     x7, [x5]
    ldr     w7, [x6, #8]
    str     w7, [x5, #8]
    add     x4, x5, #12
    mov     x6, #28
hexloop:
    lsr     w7, w21, w6
    and     w7, w7, #15
    cmp     w7, #10
    b.lt    1f
    add     w7, w7, #87
    b       2f
1:  add     w7, w7, #48
2:  strb    w7, [x4], #1
    subs    x6, x6, #4
    b.pl    hexloop
    mov     w7, #10
    strb    w7, [x4]
    mov     x8, #64
    mov     x0, #1
    mov     x1, x5
    mov     x2, #21
    svc     #0

    adrp    x5, req
    add     x5, x5, :lo12:req

    // CreateWindow (opcode 1), 32 bytes
    mov     w7, #1
    strb    w7, [x5]
    strb    w25, [x5, #1]           // depth
    mov     w7, #8
    strh    w7, [x5, #2]
    str     w21, [x5, #4]           // window_id
    str     w23, [x5, #8]           // parent = root
    str     wzr, [x5, #12]          // x=0, y=0
    mov     w7, #300
    strh    w7, [x5, #16]
    strh    w7, [x5, #18]
    strh    wzr, [x5, #20]
    mov     w7, #1
    strh    w7, [x5, #22]           // class = InputOutput
    str     w24, [x5, #24]          // visual
    str     wzr, [x5, #28]
    mov     x8, #64
    mov     x0, x19
    mov     x1, x5
    mov     x2, #32
    svc     #0

    // MapWindow (opcode 8), 8 bytes
    mov     w7, #8
    strb    w7, [x5]
    strb    wzr, [x5, #1]
    mov     w7, #2
    strh    w7, [x5, #2]
    str     w21, [x5, #4]
    mov     x8, #64
    mov     x0, x19
    mov     x1, x5
    mov     x2, #8
    svc     #0

    // nanosleep 300ms
    sub     sp, sp, #16
    str     xzr, [sp]
    mov     x7, #0xa300
    movk    x7, #0x11e1, lsl #16
    str     x7, [sp, #8]
    mov     x8, #101
    mov     x0, sp
    mov     x1, #0
    svc     #0

    // CreateGC (opcode 55), 20 bytes
    mov     w7, #55
    strb    w7, [x5]
    strb    wzr, [x5, #1]
    mov     w7, #5
    strh    w7, [x5, #2]
    str     w22, [x5, #4]           // gc_id
    str     w21, [x5, #8]           // drawable = window
    mov     w7, #4
    str     w7, [x5, #12]           // GCForeground
    mov     w7, #0xff00
    str     w7, [x5, #16]           // green
    mov     x8, #64
    mov     x0, x19
    mov     x1, x5
    mov     x2, #20
    svc     #0

    // PolyFillRectangle (opcode 70), 20 bytes
    mov     w7, #70
    strb    w7, [x5]
    strb    wzr, [x5, #1]
    mov     w7, #5
    strh    w7, [x5, #2]
    str     w21, [x5, #4]           // drawable
    str     w22, [x5, #8]           // gc
    str     wzr, [x5, #12]          // x=0, y=0
    mov     w7, #300
    strh    w7, [x5, #16]
    strh    w7, [x5, #18]
    mov     x8, #64
    mov     x0, x19
    mov     x1, x5
    mov     x2, #20
    svc     #0

    // nanosleep 4s
    mov     x7, #4
    str     x7, [sp]
    str     xzr, [sp, #8]
    mov     x8, #101
    mov     x0, sp
    mov     x1, #0
    svc     #0

    mov     x8, #94
    mov     x0, #0
    svc     #0

auth_fail:
    mov     x8, #64
    mov     x0, #1
    adrp    x1, authmsg
    add     x1, x1, :lo12:authmsg
    mov     x2, #12
    svc     #0
die1:
    mov     x8, #94
    mov     x0, #1
    svc     #0
