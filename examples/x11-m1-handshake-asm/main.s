    .text
    .global _start

_start:
    // socket(AF_UNIX=1, SOCK_STREAM=1, 0)
    mov     x0, #1
    mov     x1, #1
    mov     x2, #0
    mov     x8, #198
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0                 // socket fd

    // connect(fd, &sockaddr, 110)
    mov     x0, x19
    adrp    x1, sockaddr
    add     x1, x1, :lo12:sockaddr
    mov     x2, #110
    mov     x8, #203
    svc     #0
    cmp     x0, #0
    b.lt    fail

    // write the 48-byte setup request, looping on short writes
    mov     x20, #0                 // bytes sent so far
send_loop:
    mov     x0, x19
    adrp    x1, request
    add     x1, x1, :lo12:request
    add     x1, x1, x20
    mov     x2, #48
    sub     x2, x2, x20
    mov     x8, #64
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x20, x20, x0
    cmp     x20, #48
    b.lt    send_loop

    // read exactly 8 bytes of reply header into buf[0..8)
    adrp    x21, buf
    add     x21, x21, :lo12:buf
    mov     x20, #0                 // bytes read so far
hdr_loop:
    mov     x0, x19
    add     x1, x21, x20
    mov     x2, #8
    sub     x2, x2, x20
    mov     x8, #63
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x20, x20, x0
    cmp     x20, #8
    b.lt    hdr_loop

    // success byte must be 1
    ldrb    w0, [x21]
    cmp     w0, #1
    b.ne    auth_fail

    // read addl_len*4 more bytes into buf[8..8+addl_len*4)
    ldrh    w22, [x21, #6]          // addl_len (units of 4 bytes)
    lsl     x22, x22, #2            // byte count
    mov     x20, #0                 // body bytes read so far
body_loop:
    cmp     x20, x22
    b.ge    parse
    mov     x0, x19
    add     x1, x21, #8
    add     x1, x1, x20
    sub     x2, x22, x20
    mov     x8, #63
    svc     #0
    cmp     x0, #0
    b.le    fail
    add     x20, x20, x0
    b       body_loop

parse:
    // vendor_end = 40 + ((vendor_len + 3) & ~3)
    ldrh    w0, [x21, #24]          // vendor_len
    add     w0, w0, #3
    and     w0, w0, #0xfffffffc
    add     w0, w0, #40
    // root_offset = vendor_end + num_formats * 8
    ldrb    w1, [x21, #29]          // num_formats
    add     w0, w0, w1, lsl #3
    // root_window_id = u32 LE at buf[root_offset]
    ldr     w23, [x21, x0]
    // root_visual_id = u32 LE at buf[root_offset + 32]
    add     x0, x0, #32
    ldr     w24, [x21, x0]

    // convert both values to 8 lowercase hex digits in the output template
    mov     w0, w23
    adrp    x1, hex1
    add     x1, x1, :lo12:hex1
    bl      hexify
    mov     w0, w24
    adrp    x1, hex2
    add     x1, x1, :lo12:hex2
    bl      hexify

    // write(1, msg, 46)
    mov     x0, #1
    adrp    x1, msg
    add     x1, x1, :lo12:msg
    mov     x2, #46
    mov     x8, #64
    svc     #0

    // exit_group(0)
    mov     x0, #0
    mov     x8, #94
    svc     #0

auth_fail:
    mov     x0, #1
    adrp    x1, authmsg
    add     x1, x1, :lo12:authmsg
    mov     x2, #12
    mov     x8, #64
    svc     #0
fail:
    // exit_group(1)
    mov     x0, #1
    mov     x8, #94
    svc     #0

// hexify: write w0 as 8 lowercase hex ASCII digits (MSB first) to [x1]
hexify:
    mov     w2, #28                 // shift amount, 28 down to 0
hex_loop:
    lsr     w3, w0, w2
    and     w3, w3, #0xf
    cmp     w3, #10
    b.lt    hex_digit
    add     w3, w3, #87             // 10..15 -> 'a'..'f'
    b       hex_store
hex_digit:
    add     w3, w3, #48             // 0..9 -> '0'..'9'
hex_store:
    strb    w3, [x1], #1
    subs    w2, w2, #4
    b.ge    hex_loop
    ret

    .data
sockaddr:
    .hword  1                       // sa_family = AF_UNIX
    .ascii  "/tmp/.X11-unix/X0"     // 17 bytes
    .zero   91                      // NUL + zero-pad sun_path to 108 bytes

request:
    .byte   0x6c, 0                 // 'l' little-endian, unused
    .hword  11                      // protocol-major-version
    .hword  0                       // protocol-minor-version
    .hword  18                      // auth-protocol-name length
    .hword  16                      // auth-protocol-data length
    .hword  0                       // unused
    .ascii  "MIT-MAGIC-COOKIE-1"    // 18 bytes
    .byte   0, 0                    // pad to 20
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

msg:
    .ascii  "root_window=0x"
hex1:
    .ascii  "________\n"
    .ascii  "root_visual=0x"
hex2:
    .ascii  "________\n"

authmsg:
    .ascii  "AUTH FAILED\n"

    .bss
    .balign 8
buf:
    .zero   16384
