    .data
    .balign 8
sockaddr:
    .hword 1
    .ascii "/tmp/.X11-unix/X0"
    .byte 0
    .space 90
    .balign 8
setup_req:
    .byte 0x6c, 0
    .hword 11, 0, 18, 16, 0
    .ascii "MIT-MAGIC-COOKIE-1"
    .byte 0, 0
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .balign 8
ts300:
    .quad 0
    .quad 300000000
ts25:
    .quad 0
    .quad 25000000
msg_wid:
    .ascii "window_id=0x"
msg_press:
    .ascii "press "
msg_release:
    .ascii "release "

    .bss
    .balign 8
resp:
    .space 16384
    .balign 8
evbuf:
    .space 4096
    .balign 8
numbuf:
    .space 32
    .balign 8
cwreq:
    .space 40
    .balign 8
mapreq:
    .space 8

    .text
    .global _start
_start:
    // socket(AF_UNIX, SOCK_STREAM, 0)
    mov x0, #1
    mov x1, #1
    mov x2, #0
    mov x8, #198
    svc #0
    cmp x0, #0
    b.lt fail
    mov x19, x0

    // connect(fd, sockaddr, 110)
    mov x0, x19
    adrp x1, sockaddr
    add x1, x1, :lo12:sockaddr
    mov x2, #110
    mov x8, #203
    svc #0
    cmp x0, #0
    b.lt fail

    // write setup request (48 bytes)
    mov x0, x19
    adrp x1, setup_req
    add x1, x1, :lo12:setup_req
    mov x2, #48
    mov x8, #64
    svc #0
    cmp x0, #0
    b.lt fail

    // read 8-byte reply header
    adrp x27, resp
    add x27, x27, :lo12:resp
    mov x0, x19
    mov x1, x27
    mov x2, #8
    bl read_full

    ldrb w0, [x27]
    cmp w0, #1
    b.ne fail

    // read addl_len*4 body bytes
    ldrh w2, [x27, #6]
    lsl x2, x2, #2
    mov x0, x19
    add x1, x27, #8
    bl read_full

    // parse setup reply
    ldr w0, [x27, #12]          // resource_id_base
    orr w20, w0, #1             // window_id
    ldrh w1, [x27, #24]         // vendor_len
    add w1, w1, #3
    and w1, w1, #0xfffffffc
    ldrb w2, [x27, #29]         // num_formats
    add w3, w1, #40
    add w3, w3, w2, lsl #3      // root_offset
    add x4, x27, w3, uxtw
    ldr w21, [x4]               // root_window_id
    ldr w22, [x4, #32]          // root_visual_id
    ldrb w23, [x4, #38]         // root_depth

    // print "window_id=0x........\n"
    adrp x1, msg_wid
    add x1, x1, :lo12:msg_wid
    mov x2, #12
    bl write_out
    mov w0, w20
    bl print_hex32

    // CreateWindow (36 bytes, CWEventMask = KeyPress|KeyRelease)
    adrp x4, cwreq
    add x4, x4, :lo12:cwreq
    mov w0, #1
    strb w0, [x4]
    strb w23, [x4, #1]
    mov w0, #9
    strh w0, [x4, #2]
    str w20, [x4, #4]
    str w21, [x4, #8]
    str wzr, [x4, #12]
    mov w0, #200
    strh w0, [x4, #16]
    mov w0, #100
    strh w0, [x4, #18]
    strh wzr, [x4, #20]
    mov w0, #1
    strh w0, [x4, #22]
    str w22, [x4, #24]
    mov w0, #0x800
    str w0, [x4, #28]
    mov w0, #3
    str w0, [x4, #32]
    mov x0, x19
    mov x1, x4
    mov x2, #36
    mov x8, #64
    svc #0
    cmp x0, #0
    b.lt fail

    // MapWindow (8 bytes)
    adrp x4, mapreq
    add x4, x4, :lo12:mapreq
    mov w0, #8
    strb w0, [x4]
    strb wzr, [x4, #1]
    mov w0, #2
    strh w0, [x4, #2]
    str w20, [x4, #4]
    mov x0, x19
    mov x1, x4
    mov x2, #8
    mov x8, #64
    svc #0
    cmp x0, #0
    b.lt fail

    // nanosleep 300ms
    adrp x0, ts300
    add x0, x0, :lo12:ts300
    mov x1, #0
    mov x8, #101
    svc #0

    // fcntl(fd, F_SETFL, O_NONBLOCK)
    mov x0, x19
    mov x1, #4
    mov x2, #0x800
    mov x8, #25
    svc #0

    mov x24, #200
outer:
inner:
    mov x0, x19
    adrp x1, evbuf
    add x1, x1, :lo12:evbuf
    mov x2, #4096
    mov x8, #63
    svc #0
    cmp x0, #0
    b.le sleep25                // -EAGAIN or EOF: nothing now
    adrp x25, evbuf
    add x25, x25, :lo12:evbuf
    mov x26, x0
chunk:
    cmp x26, #32
    b.lt inner
    ldrb w0, [x25]
    and w0, w0, #0x7f
    cmp w0, #2
    b.eq do_press
    cmp w0, #3
    b.eq do_release
next_chunk:
    add x25, x25, #32
    sub x26, x26, #32
    b chunk
do_press:
    adrp x1, msg_press
    add x1, x1, :lo12:msg_press
    mov x2, #6
    bl write_out
    ldrb w0, [x25, #1]
    bl print_dec
    b next_chunk
do_release:
    adrp x1, msg_release
    add x1, x1, :lo12:msg_release
    mov x2, #8
    bl write_out
    ldrb w0, [x25, #1]
    bl print_dec
    b next_chunk
sleep25:
    adrp x0, ts25
    add x0, x0, :lo12:ts25
    mov x1, #0
    mov x8, #101
    svc #0
    subs x24, x24, #1
    b.ne outer

    mov x0, #0
    mov x8, #94
    svc #0

// read exactly x2 bytes from fd x0 into x1
read_full:
    mov x9, x0
    mov x10, x1
    mov x11, x2
1:
    cbz x11, 3f
    mov x0, x9
    mov x1, x10
    mov x2, x11
    mov x8, #63
    svc #0
    cmp x0, #0
    b.le fail
    add x10, x10, x0
    sub x11, x11, x0
    b 1b
3:
    ret

// write(1, x1, x2)
write_out:
    mov x0, #1
    mov x8, #64
    svc #0
    ret

// print w0 as 8 uppercase hex digits + newline
print_hex32:
    adrp x1, numbuf
    add x1, x1, :lo12:numbuf
    mov x2, x1
    mov w3, #28
    mov w5, #8
1:
    lsr w4, w0, w3
    and w4, w4, #0xf
    cmp w4, #10
    b.lt 2f
    add w4, w4, #55
    b 3f
2:
    add w4, w4, #48
3:
    strb w4, [x1], #1
    sub w3, w3, #4
    subs w5, w5, #1
    b.ne 1b
    mov w4, #10
    strb w4, [x1]
    mov x0, #1
    mov x1, x2
    mov x2, #9
    mov x8, #64
    svc #0
    ret

// print w0 (0-255) in decimal + newline
print_dec:
    adrp x3, numbuf
    add x3, x3, :lo12:numbuf
    add x3, x3, #16
    mov w6, #10
    sub x3, x3, #1
    strb w6, [x3]
    mov x4, #1
    mov w5, #10
1:
    udiv w6, w0, w5
    msub w7, w6, w5, w0
    add w7, w7, #48
    sub x3, x3, #1
    strb w7, [x3]
    add x4, x4, #1
    mov w0, w6
    cbnz w0, 1b
    mov x0, #1
    mov x1, x3
    mov x2, x4
    mov x8, #64
    svc #0
    ret

fail:
    mov x0, #1
    mov x8, #94
    svc #0
