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

    // connect
    mov x0, x19
    adrp x1, sockaddr
    add x1, x1, :lo12:sockaddr
    mov x2, #110
    mov x8, #203
    svc #0
    cmp x0, #0
    b.lt fail

    // send setup request
    mov x0, x19
    adrp x1, setup_req
    add x1, x1, :lo12:setup_req
    mov x2, #48
    bl write_all

    // read 8-byte header
    adrp x1, resp
    add x1, x1, :lo12:resp
    mov x2, #8
    bl read_exact

    // read additional data
    adrp x1, resp
    add x1, x1, :lo12:resp
    ldrh w2, [x1, #6]
    lsl w2, w2, #2
    add x1, x1, #8
    bl read_exact

    adrp x1, resp
    add x1, x1, :lo12:resp
    ldrb w0, [x1]
    cmp w0, #1
    b.ne fail

    ldr w20, [x1, #12]          // resource_id_base
    ldrh w2, [x1, #24]          // vendor_len
    ldrb w3, [x1, #29]          // num_formats
    add w2, w2, #3
    and w2, w2, #0xfffffffc
    add w4, w2, #40
    add w4, w4, w3, lsl #3      // root_offset
    add x5, x1, w4, uxtw
    ldr w22, [x5]               // root window
    ldr w23, [x5, #32]          // root visual
    ldrb w24, [x5, #38]         // root depth
    orr w21, w20, #1            // window_id

    // print window_id=0x........
    mov w0, w21
    adrp x1, winhex
    add x1, x1, :lo12:winhex
    bl u32_hex
    mov x0, #1
    adrp x1, winmsg
    add x1, x1, :lo12:winmsg
    mov x2, #21
    bl write_all

    // CreateWindow
    adrp x10, reqbuf
    add x10, x10, :lo12:reqbuf
    mov w0, #1
    strb w0, [x10]
    strb w24, [x10, #1]
    mov w0, #9
    strh w0, [x10, #2]
    str w21, [x10, #4]
    str w22, [x10, #8]
    strh wzr, [x10, #12]
    strh wzr, [x10, #14]
    mov w0, #300
    strh w0, [x10, #16]
    mov w0, #200
    strh w0, [x10, #18]
    strh wzr, [x10, #20]
    mov w0, #1
    strh w0, [x10, #22]
    str w23, [x10, #24]
    mov w0, #0x800
    str w0, [x10, #28]
    mov w0, #3
    str w0, [x10, #32]
    mov x0, x19
    mov x1, x10
    mov x2, #36
    bl write_all

    // MapWindow
    adrp x10, reqbuf
    add x10, x10, :lo12:reqbuf
    mov w0, #8
    strb w0, [x10]
    strb wzr, [x10, #1]
    mov w0, #2
    strh w0, [x10, #2]
    str w21, [x10, #4]
    mov x0, x19
    mov x1, x10
    mov x2, #8
    bl write_all

    // sleep 300ms
    adrp x0, ts300
    add x0, x0, :lo12:ts300
    mov x1, #0
    mov x8, #101
    svc #0

    // three GCs
    orr w0, w20, #2
    mov w1, #0x3050
    movk w1, #0x30, lsl #16
    bl make_gc
    orr w0, w20, #3
    mov w1, #0x4030
    movk w1, #0x50, lsl #16
    bl make_gc
    orr w0, w20, #4
    mov w1, #0x9090
    movk w1, #0x90, lsl #16
    bl make_gc

    // fcntl(fd, F_SETFL, O_NONBLOCK)
    mov x0, x19
    mov x1, #4
    mov x2, #0x800
    mov x8, #25
    svc #0

    mov w25, #0
main_loop:
    bl poll_input
    bl update_player
    bl render
    mov x0, #1
    adrp x1, frame_str
    add x1, x1, :lo12:frame_str
    mov x2, #6
    bl write_all
    mov w0, w25
    bl print_dec_nl
    adrp x0, ts80
    add x0, x0, :lo12:ts80
    mov x1, #0
    mov x8, #101
    svc #0
    add w25, w25, #1
    cmp w25, #200
    b.lt main_loop
    mov x0, #0
    mov x8, #94
    svc #0

fail:
    mov x0, #1
    mov x8, #94
    svc #0

// ---- poll all pending X events, update key flags ----
poll_input:
    stp x29, x30, [sp, #-16]!
pi_read:
    mov x0, x19
    adrp x1, evbuf
    add x1, x1, :lo12:evbuf
    mov x2, #4096
    mov x8, #63
    svc #0
    cmp x0, #0
    b.le pi_done
    adrp x4, evbuf
    add x4, x4, :lo12:evbuf
    mov x5, x0
pi_chunk:
    cmp x5, #32
    b.lt pi_read
    ldrb w6, [x4]
    and w6, w6, #0x7f
    ldrb w7, [x4, #1]
    cmp w6, #2
    b.eq pi_press
    cmp w6, #3
    b.eq pi_release
    b pi_next
pi_press:
    stp x4, x5, [sp, #-32]!
    stp x6, x7, [sp, #16]
    mov x0, #1
    adrp x1, press_str
    add x1, x1, :lo12:press_str
    mov x2, #6
    bl write_all
    ldr x7, [sp, #24]
    mov w0, w7
    bl print_dec_nl
    ldp x6, x7, [sp, #16]
    ldp x4, x5, [sp], #32
    b pi_key
pi_release:
    stp x4, x5, [sp, #-32]!
    stp x6, x7, [sp, #16]
    mov x0, #1
    adrp x1, release_str
    add x1, x1, :lo12:release_str
    mov x2, #8
    bl write_all
    ldr x7, [sp, #24]
    mov w0, w7
    bl print_dec_nl
    ldp x6, x7, [sp, #16]
    ldp x4, x5, [sp], #32
pi_key:
    cmp w6, #2
    cset w8, eq
    cmp w7, #25
    b.ne pi_k2
    adrp x9, key_forward
    add x9, x9, :lo12:key_forward
    strb w8, [x9]
    b pi_next
pi_k2:
    cmp w7, #39
    b.ne pi_k3
    adrp x9, key_backward
    add x9, x9, :lo12:key_backward
    strb w8, [x9]
    b pi_next
pi_k3:
    cmp w7, #38
    b.ne pi_k4
    adrp x9, key_left
    add x9, x9, :lo12:key_left
    strb w8, [x9]
    b pi_next
pi_k4:
    cmp w7, #40
    b.ne pi_next
    adrp x9, key_right
    add x9, x9, :lo12:key_right
    strb w8, [x9]
pi_next:
    add x4, x4, #32
    sub x5, x5, #32
    b pi_chunk
pi_done:
    ldp x29, x30, [sp], #16
    ret

// ---- turn + move with collision ----
update_player:
    adrp x9, player_angle
    add x9, x9, :lo12:player_angle
    ldr w0, [x9]
    adrp x10, key_left
    add x10, x10, :lo12:key_left
    ldrb w1, [x10]
    cbz w1, up_1
    sub w0, w0, #3
up_1:
    adrp x10, key_right
    add x10, x10, :lo12:key_right
    ldrb w1, [x10]
    cbz w1, up_2
    add w0, w0, #3
up_2:
    and w0, w0, #255
    str w0, [x9]
    adrp x10, key_forward
    add x10, x10, :lo12:key_forward
    ldrb w1, [x10]
    adrp x10, key_backward
    add x10, x10, :lo12:key_backward
    ldrb w2, [x10]
    subs w3, w1, w2             // move_dir
    b.eq up_done
    adrp x12, sine_table
    add x12, x12, :lo12:sine_table
    add w4, w0, #64
    and w4, w4, #255
    ldrsb w5, [x12, w4, uxtw]   // cos
    ldrsb w6, [x12, w0, uxtw]   // sin
    mov w7, #6
    mul w8, w5, w7
    asr w8, w8, #7
    mul w8, w8, w3
    mul w10, w6, w7
    asr w10, w10, #7
    mul w10, w10, w3
    adrp x11, player_x
    add x11, x11, :lo12:player_x
    adrp x12, player_y
    add x12, x12, :lo12:player_y
    ldr w13, [x11]
    ldr w14, [x12]
    add w13, w13, w8            // cand_x
    add w14, w14, w10           // cand_y
    asr w15, w13, #8
    asr w16, w14, #8
    cmp w15, #7
    b.hi up_done
    cmp w16, #7
    b.hi up_done
    adrp x17, map
    add x17, x17, :lo12:map
    add w1, w15, w16, lsl #3
    ldrb w2, [x17, w1, uxtw]
    cmp w2, #1
    b.eq up_done
    str w13, [x11]
    str w14, [x12]
up_done:
    ret

// ---- raycast all 300 columns, draw ceiling/floor/walls ----
render:
    stp x29, x30, [sp, #-16]!
    adrp x0, player_x
    add x0, x0, :lo12:player_x
    ldr w9, [x0]
    adrp x0, player_y
    add x0, x0, :lo12:player_y
    ldr w10, [x0]
    adrp x0, player_angle
    add x0, x0, :lo12:player_angle
    ldr w11, [x0]
    adrp x12, sine_table
    add x12, x12, :lo12:sine_table
    adrp x13, tops
    add x13, x13, :lo12:tops
    adrp x14, heights
    add x14, x14, :lo12:heights
    adrp x16, map
    add x16, x16, :lo12:map
    mov w15, #0
r_col:
    mov w0, #43
    mul w0, w15, w0
    mov w1, #300
    udiv w0, w0, w1
    add w0, w0, w11
    sub w0, w0, #21
    and w0, w0, #255            // ray angle
    add w1, w0, #64
    and w1, w1, #255
    ldrsb w2, [x12, w1, uxtw]   // cos
    ldrsb w3, [x12, w0, uxtw]   // sin
    lsl w2, w2, #3
    asr w2, w2, #7              // step_x
    lsl w3, w3, #3
    asr w3, w3, #7              // step_y
    mov w4, w9
    mov w5, w10
    mov w6, #0                  // dist_fx
    mov w7, #400
r_step:
    add w4, w4, w2
    add w5, w5, w3
    add w6, w6, #8
    asr w0, w4, #8
    cmp w0, #7
    b.hi r_hit
    asr w1, w5, #8
    cmp w1, #7
    b.hi r_hit
    add w0, w0, w1, lsl #3
    ldrb w8, [x16, w0, uxtw]
    cmp w8, #1
    b.eq r_hit
    subs w7, w7, #1
    b.ne r_step
    mov w6, #3200
r_hit:
    mov w0, #51200
    udiv w0, w0, w6             // wall_h
    cmp w0, #200
    b.le r_clamped
    mov w0, #200
r_clamped:
    mov w1, #200
    sub w1, w1, w0
    lsr w1, w1, #1              // wall_top
    strh w1, [x13, w15, uxtw #1]
    strh w0, [x14, w15, uxtw #1]
    add w15, w15, #1
    cmp w15, #300
    b.lt r_col

    // ceiling
    adrp x10, reqbuf
    add x10, x10, :lo12:reqbuf
    mov w0, #70
    strb w0, [x10]
    strb wzr, [x10, #1]
    mov w0, #5
    strh w0, [x10, #2]
    str w21, [x10, #4]
    orr w0, w20, #2
    str w0, [x10, #8]
    strh wzr, [x10, #12]
    strh wzr, [x10, #14]
    mov w0, #300
    strh w0, [x10, #16]
    mov w0, #100
    strh w0, [x10, #18]
    mov x0, x19
    mov x1, x10
    mov x2, #20
    bl write_all

    // floor (reuse buffer, patch gc + y)
    adrp x10, reqbuf
    add x10, x10, :lo12:reqbuf
    orr w0, w20, #3
    str w0, [x10, #8]
    mov w0, #100
    strh w0, [x10, #14]
    mov x0, x19
    mov x1, x10
    mov x2, #20
    bl write_all

    // walls: one request, 300 rects
    adrp x10, rectbuf
    add x10, x10, :lo12:rectbuf
    mov w0, #70
    strb w0, [x10]
    strb wzr, [x10, #1]
    mov w0, #603
    strh w0, [x10, #2]
    str w21, [x10, #4]
    orr w0, w20, #4
    str w0, [x10, #8]
    add x2, x10, #12
    mov w3, #0
r_rects:
    strh w3, [x2]
    ldrh w4, [x13, w3, uxtw #1]
    strh w4, [x2, #2]
    mov w4, #1
    strh w4, [x2, #4]
    ldrh w4, [x14, w3, uxtw #1]
    strh w4, [x2, #6]
    add x2, x2, #8
    add w3, w3, #1
    cmp w3, #300
    b.lt r_rects
    mov x0, x19
    mov x1, x10
    mov x2, #2412
    bl write_all
    ldp x29, x30, [sp], #16
    ret

// ---- CreateGC: w0 = gc id, w1 = foreground ----
make_gc:
    stp x29, x30, [sp, #-16]!
    adrp x2, reqbuf
    add x2, x2, :lo12:reqbuf
    mov w3, #55
    strb w3, [x2]
    strb wzr, [x2, #1]
    mov w3, #5
    strh w3, [x2, #2]
    str w0, [x2, #4]
    str w21, [x2, #8]
    mov w3, #4
    str w3, [x2, #12]
    str w1, [x2, #16]
    mov x0, x19
    mov x1, x2
    mov x2, #20
    bl write_all
    ldp x29, x30, [sp], #16
    ret

// ---- write_all(x0 fd, x1 buf, x2 len), retries short writes/EAGAIN ----
write_all:
    mov x3, x0
wa_loop:
    cbz x2, wa_done
    mov x0, x3
    mov x8, #64
    svc #0
    cmp x0, #0
    b.le wa_loop
    add x1, x1, x0
    sub x2, x2, x0
    b wa_loop
wa_done:
    ret

// ---- read_exact(x1 buf, x2 len) from socket x19 ----
read_exact:
    cbz x2, re_done
    mov x0, x19
    mov x8, #63
    svc #0
    cmp x0, #0
    b.le fail
    add x1, x1, x0
    sub x2, x2, x0
    b read_exact
re_done:
    ret

// ---- w0 -> 8 lowercase hex chars at x1 ----
u32_hex:
    mov w3, #28
hex_loop:
    lsr w4, w0, w3
    and w4, w4, #15
    cmp w4, #10
    b.lt hex_digit
    add w4, w4, #87
    b hex_store
hex_digit:
    add w4, w4, #48
hex_store:
    strb w4, [x1], #1
    subs w3, w3, #4
    b.ge hex_loop
    ret

// ---- print decimal of w0 plus newline to stdout ----
print_dec_nl:
    stp x29, x30, [sp, #-16]!
    adrp x1, decbuf
    add x1, x1, :lo12:decbuf
    add x1, x1, #15
    mov w2, #10
    strb w2, [x1]
    mov x3, x1
    mov w4, #10
dec_loop:
    udiv w5, w0, w4
    msub w6, w5, w4, w0
    add w6, w6, #48
    sub x3, x3, #1
    strb w6, [x3]
    mov w0, w5
    cbnz w0, dec_loop
    add x2, x1, #1
    sub x2, x2, x3
    mov x1, x3
    mov x0, #1
    bl write_all
    ldp x29, x30, [sp], #16
    ret

    .data
sockaddr:
    .hword 1
    .ascii "/tmp/.X11-unix/X0"
    .byte 0
    .zero 90

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

sine_table:
    .byte 0,3,6,9,12,16,19,22,25,28,31,34,37,40,43,46
    .byte 49,51,54,57,60,63,65,68,71,73,76,78,81,83,85,88
    .byte 90,92,94,96,98,100,102,104,106,107,109,111,112,113,115,116
    .byte 117,118,120,121,122,122,123,124,125,125,126,126,126,127,127,127
    .byte 127,127,127,127,126,126,126,125,125,124,123,122,122,121,120,118
    .byte 117,116,115,113,112,111,109,107,106,104,102,100,98,96,94,92
    .byte 90,88,85,83,81,78,76,73,71,68,65,63,60,57,54,51
    .byte 49,46,43,40,37,34,31,28,25,22,19,16,12,9,6,3
    .byte 0,-3,-6,-9,-12,-16,-19,-22,-25,-28,-31,-34,-37,-40,-43,-46
    .byte -49,-51,-54,-57,-60,-63,-65,-68,-71,-73,-76,-78,-81,-83,-85,-88
    .byte -90,-92,-94,-96,-98,-100,-102,-104,-106,-107,-109,-111,-112,-113,-115,-116
    .byte -117,-118,-120,-121,-122,-122,-123,-124,-125,-125,-126,-126,-126,-127,-127,-127
    .byte -127,-127,-127,-127,-126,-126,-126,-125,-125,-124,-123,-122,-122,-121,-120,-118
    .byte -117,-116,-115,-113,-112,-111,-109,-107,-106,-104,-102,-100,-98,-96,-94,-92
    .byte -90,-88,-85,-83,-81,-78,-76,-73,-71,-68,-65,-63,-60,-57,-54,-51
    .byte -49,-46,-43,-40,-37,-34,-31,-28,-25,-22,-19,-16,-12,-9,-6,-3

map:
    .byte 1,1,1,1,1,1,1,1
    .byte 1,0,0,0,0,0,0,1
    .byte 1,0,1,1,0,1,0,1
    .byte 1,0,1,0,0,0,0,1
    .byte 1,0,0,0,1,1,0,1
    .byte 1,0,1,0,0,0,0,1
    .byte 1,0,0,0,0,1,0,1
    .byte 1,1,1,1,1,1,1,1

    .balign 4
player_x:
    .word 896
player_y:
    .word 384
player_angle:
    .word 0
key_forward:
    .byte 0
key_backward:
    .byte 0
key_left:
    .byte 0
key_right:
    .byte 0

    .balign 8
ts300:
    .quad 0
    .quad 300000000
ts80:
    .quad 0
    .quad 80000000

winmsg:
    .ascii "window_id=0x"
winhex:
    .space 8
    .ascii "\n"
press_str:
    .ascii "press "
release_str:
    .ascii "release "
frame_str:
    .ascii "frame="

    .bss
    .balign 8
resp:
    .space 65536
evbuf:
    .space 4096
reqbuf:
    .space 64
rectbuf:
    .space 2416
tops:
    .space 600
heights:
    .space 600
decbuf:
    .space 16
