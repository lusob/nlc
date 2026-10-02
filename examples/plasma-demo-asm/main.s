    .data
ramp:
    .ascii " .:-=+*#%@X$&8BW"
sine:
    .byte 8,8,9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10,9,8,8,7,6,5,5,4,3,3,2,2,1,1,1,0,0,0,0,0,0,0,1,1,1,2,2,3,3,4,5,5,6,7
    .balign 8
ts:
    .quad 0
    .quad 50000000

    .bss
    .balign 8
buf:
    .skip 1300

    .text
    .global _start
_start:
    mov x19, #0                 // t = frame counter
frame_loop:
    adrp x20, buf
    add x20, x20, :lo12:buf
    mov x9, x20                 // x9 = write cursor into buf
    cbnz x19, no_clear
    mov w10, #0x1B              // frame 0: ESC [ 2 J
    strb w10, [x9], #1
    mov w10, #0x5B
    strb w10, [x9], #1
    mov w10, #0x32
    strb w10, [x9], #1
    mov w10, #0x4A
    strb w10, [x9], #1
no_clear:
    mov w10, #0x1B              // ESC [ H
    strb w10, [x9], #1
    mov w10, #0x5B
    strb w10, [x9], #1
    mov w10, #0x48
    strb w10, [x9], #1

    adrp x21, ramp
    add x21, x21, :lo12:ramp
    adrp x22, sine
    add x22, x22, :lo12:sine

    mov x11, #0                 // row
row_loop:
    add x13, x11, x11, lsl #1   // row*3
    add x13, x13, x19, lsl #1   // + t*2
    and x13, x13, #63
    ldrb w13, [x22, x13]        // sine[idx2], constant across the row
    mov x12, #0                 // col
col_loop:
    add x14, x19, x12, lsl #1   // col*2 + t
    and x14, x14, #63
    ldrb w14, [x22, x14]        // sine[idx1]
    add w14, w14, w13           // sum 0..30
    lsr w14, w14, #1            // level 0..15
    ldrb w14, [x21, x14]        // ramp[level]
    strb w14, [x9], #1
    add x12, x12, #1
    cmp x12, #60
    b.lt col_loop
    mov w10, #0x0A
    strb w10, [x9], #1
    add x11, x11, #1
    cmp x11, #20
    b.lt row_loop

    mov x0, #1                  // write(1, buf, len)
    mov x1, x20
    sub x2, x9, x20
    mov x8, #64
    svc #0

    adrp x0, ts                 // nanosleep(&ts, NULL)
    add x0, x0, :lo12:ts
    mov x1, #0
    mov x8, #101
    svc #0

    add x19, x19, #1
    cmp x19, #64
    b.lt frame_loop

    mov x0, #0                  // exit_group(0)
    mov x8, #94
    svc #0
