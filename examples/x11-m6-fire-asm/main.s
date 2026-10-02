    .text
    .global _start

_start:
    // socket(AF_UNIX, SOCK_STREAM, 0)
    mov x0, #1
    mov x1, #1
    mov x2, #0
    mov x8, #198
    svc #0
    tbnz x0, #63, fail
    mov x19, x0

    // connect
    adrp x1, sockaddr
    add x1, x1, :lo12:sockaddr
    mov x2, #110
    mov x8, #203
    svc #0
    cbnz x0, fail

    // send 48-byte setup request
    adrp x1, setup_req
    add x1, x1, :lo12:setup_req
    mov x2, #48
    bl send_all

    // read 8-byte header, then addl_len*4 bytes
    adrp x25, rbuf
    add x25, x25, :lo12:rbuf
    mov x1, x25
    mov x2, #8
    bl recv_all
    ldrh w2, [x25, #6]
    lsl x2, x2, #2
    add x1, x25, #8
    bl recv_all
    ldrb w0, [x25]
    cmp w0, #1
    bne fail

    // parse setup reply
    ldr w26, [x25, #12]         // resource_id_base
    orr w20, w26, #1            // window_id
    orr w21, w26, #2            // gc_id

    ldrh w2, [x25, #24]         // vendor_len
    add w2, w2, #3
    and w2, w2, #0xfffffffc
    ldrb w3, [x25, #29]         // num_formats
    add w2, w2, w3, lsl #3
    add w2, w2, #40             // root_offset
    add x4, x25, w2, uxtw
    ldr w27, [x4]               // root_window_id
    ldr w28, [x4, #32]          // root_visual_id
    ldrb w29, [x4, #38]         // root_depth

    // print window_id=0x........
    adrp x1, widmsg
    add x1, x1, :lo12:widmsg
    add x3, x1, #12
    mov w2, w20
    mov x5, #8
hexlp:
    lsr w4, w2, #28
    add w4, w4, #48
    cmp w4, #57
    ble 1f
    add w4, w4, #39
1:  strb w4, [x3], #1
    lsl w2, w2, #4
    subs x5, x5, #1
    bne hexlp
    mov x0, #1
    mov x2, #21
    mov x8, #64
    svc #0

    // CreateWindow (opcode 1, 32 bytes)
    mov w0, #1
    strb w0, [x25]
    strb w29, [x25, #1]
    mov w0, #8
    strh w0, [x25, #2]
    str w20, [x25, #4]
    str w27, [x25, #8]
    str wzr, [x25, #12]
    mov w0, #100
    strh w0, [x25, #16]
    mov w0, #50
    strh w0, [x25, #18]
    strh wzr, [x25, #20]
    mov w0, #1
    strh w0, [x25, #22]
    str w28, [x25, #24]
    str wzr, [x25, #28]
    mov x1, x25
    mov x2, #32
    bl send_all

    // MapWindow (opcode 8, 8 bytes)
    mov w0, #8
    strb w0, [x25]
    strb wzr, [x25, #1]
    mov w0, #2
    strh w0, [x25, #2]
    str w20, [x25, #4]
    mov x1, x25
    mov x2, #8
    bl send_all

    // sleep 300ms
    mov x0, #0
    movz x1, #0xA300
    movk x1, #0x11E1, lsl #16
    bl do_sleep

    // CreateGC (opcode 55, 20 bytes)
    mov w0, #55
    strb w0, [x25]
    strb wzr, [x25, #1]
    mov w0, #5
    strh w0, [x25, #2]
    str w21, [x25, #4]
    str w20, [x25, #8]
    mov w0, #4
    str w0, [x25, #12]
    str wzr, [x25, #16]
    mov x1, x25
    mov x2, #20
    bl send_all

    // fill fixed PutImage header once
    adrp x26, putimg_req
    add x26, x26, :lo12:putimg_req
    mov w0, #72
    strb w0, [x26]
    mov w0, #2
    strb w0, [x26, #1]
    mov w0, #5006
    strh w0, [x26, #2]
    str w20, [x26, #4]
    str w21, [x26, #8]
    mov w0, #100
    strh w0, [x26, #12]
    mov w0, #50
    strh w0, [x26, #14]
    str wzr, [x26, #16]
    strb wzr, [x26, #20]
    mov w0, #24
    strb w0, [x26, #21]
    strh wzr, [x26, #22]

    // persistent pointers for frame loop
    adrp x25, rand_seed
    add x25, x25, :lo12:rand_seed
    adrp x27, palette
    add x27, x27, :lo12:palette
    adrp x28, pixbuf
    add x28, x28, :lo12:pixbuf
    mov x22, #0                 // t

frame_loop:
    // pick current/next by t&1
    adrp x23, buf_a
    add x23, x23, :lo12:buf_a
    adrp x24, buf_b
    add x24, x24, :lo12:buf_b
    tbz x22, #0, 1f
    mov x0, x23
    mov x23, x24
    mov x24, x0
1:
    // seed bottom row of next
    mov x9, #4900
    add x9, x24, x9
    mov x10, #100
seed_loop:
    bl rand
    and w0, w0, #63
    add w0, w0, #180
    strb w0, [x9], #1
    subs x10, x10, #1
    bne seed_loop

    // propagate upward
    mov x9, #0                  // y
    mov x12, x24                // next row ptr
    add x13, x23, #100          // current row y+1 ptr
    mov w11, #99
prop_y:
    mov x10, #0                 // x
prop_x:
    ldrb w14, [x13, x10]        // below
    sub w15, w10, #1
    cmp w10, #0
    csel w15, w11, w15, eq
    ldrb w15, [x13, w15, uxtw]  // left (wrap)
    add w16, w10, #1
    cmp w10, w11
    csel w16, wzr, w16, eq
    ldrb w16, [x13, w16, uxtw]  // right (wrap)
    add w14, w14, w15
    add w14, w14, w16
    mov w15, #3
    udiv w14, w14, w15          // avg
    bl rand
    and w0, w0, #7
    add w0, w0, #4              // cooling
    subs w14, w14, w0
    csel w14, wzr, w14, lo      // clamp at 0
    strb w14, [x12, x10]
    add x10, x10, #1
    cmp x10, #100
    blt prop_x
    add x12, x12, #100
    add x13, x13, #100
    add x9, x9, #1
    cmp x9, #49
    blt prop_y

    // render next through palette into pixbuf
    mov x9, #0
    mov x13, x28
    mov x11, #5000
render_loop:
    ldrb w14, [x24, x9]
    add w15, w14, w14, lsl #1   // v*3
    ldrb w16, [x27, w15, uxtw]  // R
    add w15, w15, #1
    ldrb w17, [x27, w15, uxtw]  // G
    add w15, w15, #1
    ldrb w14, [x27, w15, uxtw]  // B
    lsl w16, w16, #16
    orr w16, w16, w17, lsl #8
    orr w16, w16, w14
    str w16, [x13], #4
    add x9, x9, #1
    cmp x9, x11
    blt render_loop

    // PutImage: header + pixels in one write
    mov x1, x26
    mov x2, #20024
    bl send_all

    // print frame=N
    sub sp, sp, #16
    add x1, sp, #15
    mov w0, #10
    strb w0, [x1]
    mov w14, w22
    mov w15, #10
digit_loop:
    udiv w16, w14, w15
    msub w17, w16, w15, w14
    add w17, w17, #48
    sub x1, x1, #1
    strb w17, [x1]
    mov w14, w16
    cbnz w14, digit_loop
    sub x1, x1, #6
    mov w0, #102                // 'f'
    strb w0, [x1]
    mov w0, #114                // 'r'
    strb w0, [x1, #1]
    mov w0, #97                 // 'a'
    strb w0, [x1, #2]
    mov w0, #109                // 'm'
    strb w0, [x1, #3]
    mov w0, #101                // 'e'
    strb w0, [x1, #4]
    mov w0, #61                 // '='
    strb w0, [x1, #5]
    add x2, sp, #16
    sub x2, x2, x1
    mov x0, #1
    mov x8, #64
    svc #0
    add sp, sp, #16

    // sleep 80ms
    mov x0, #0
    movz x1, #0xB400
    movk x1, #0x04C4, lsl #16
    bl do_sleep

    add x22, x22, #1
    cmp x22, #200
    blt frame_loop

    // final 1s sleep, then exit
    mov x0, #1
    mov x1, #0
    bl do_sleep
    mov x0, #0
    mov x8, #94
    svc #0

fail:
    mov x0, #1
    mov x8, #94
    svc #0

// x1=buf x2=len, fd in x19
send_all:
1:  cbz x2, 2f
    mov x0, x19
    mov x8, #64
    svc #0
    cmp x0, #0
    ble fail
    add x1, x1, x0
    sub x2, x2, x0
    b 1b
2:  ret

recv_all:
1:  cbz x2, 2f
    mov x0, x19
    mov x8, #63
    svc #0
    cmp x0, #0
    ble fail
    add x1, x1, x0
    sub x2, x2, x0
    b 1b
2:  ret

// LCG: seed = seed*1103515245+12345, return seed>>16 in w0
rand:
    ldr w0, [x25]
    movz w1, #0x4E6D
    movk w1, #0x41C6, lsl #16
    mul w0, w0, w1
    mov w1, #12345
    add w0, w0, w1
    str w0, [x25]
    lsr w0, w0, #16
    ret

// x0=sec x1=nsec
do_sleep:
    sub sp, sp, #16
    stp x0, x1, [sp]
    mov x0, sp
    mov x1, #0
    mov x8, #101
    svc #0
    add sp, sp, #16
    ret

    .data
sockaddr:
    .hword 1
    .ascii "/tmp/.X11-unix/X0"
    .zero 91

setup_req:
    .byte 0x6c, 0
    .hword 11
    .hword 0
    .hword 18
    .hword 16
    .hword 0
    .ascii "MIT-MAGIC-COOKIE-1"
    .byte 0, 0
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

widmsg:
    .ascii "window_id=0x00000000\n"

    .balign 4
rand_seed:
    .word 12345

palette:
    .set pv, 0
    .rept 86
    .byte pv, 0, 0
    .set pv, pv+3
    .endr
    .set pv, 3
    .rept 85
    .byte 255, pv, 0
    .set pv, pv+3
    .endr
    .set pv, 3
    .rept 85
    .byte 255, 255, pv
    .set pv, pv+3
    .endr

    .bss
rbuf:
    .skip 32768
buf_a:
    .skip 5000
buf_b:
    .skip 5000
    .balign 4
putimg_req:
    .skip 24
pixbuf:
    .skip 20000
