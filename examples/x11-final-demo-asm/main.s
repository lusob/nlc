	.macro laddr reg, sym
	adrp \reg, \sym
	add \reg, \reg, :lo12:\sym
	.endm

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

	// connect(fd, sockaddr_un, 110)
	mov x0, x19
	laddr x1, sockaddr
	mov x2, #110
	mov x8, #203
	svc #0
	cmp x0, #0
	b.lt fail

	// 48-byte setup request
	laddr x1, setup_req
	mov x2, #48
	bl send_all

	// read 8-byte header, then addl_len*4 bytes
	laddr x1, reply_buf
	mov x2, #8
	bl read_full
	laddr x9, reply_buf
	ldrh w2, [x9, #6]
	lsl w2, w2, #2
	add x1, x9, #8
	bl read_full
	laddr x9, reply_buf
	ldrb w0, [x9]
	cmp w0, #1
	b.ne fail

	// parse setup reply
	ldr w20, [x9, #12]          // resource_id_base
	ldrh w0, [x9, #24]          // vendor_len
	add w0, w0, #3
	and w0, w0, #0xFFFFFFFC
	ldrb w1, [x9, #29]          // num_formats
	add w0, w0, #40
	add w0, w0, w1, lsl #3
	add x10, x9, w0, uxtw
	ldr w25, [x10]              // root window
	ldr w26, [x10, #32]         // root visual
	ldrb w27, [x10, #38]        // root depth
	orr w21, w20, #1            // window_id

	// print window_id=0x........
	mov x0, #1
	laddr x1, wid_str
	mov x2, #12
	mov x8, #64
	svc #0
	laddr x3, numbuf
	mov w4, #28
1:	lsr w5, w21, w4
	and w5, w5, #15
	add w5, w5, #48
	cmp w5, #58
	b.lt 2f
	add w5, w5, #39
2:	strb w5, [x3], #1
	subs w4, w4, #4
	b.ge 1b
	mov w5, #10
	strb w5, [x3]
	mov x0, #1
	laddr x1, numbuf
	mov x2, #9
	mov x8, #64
	svc #0

	// CreateWindow (opcode 1)
	laddr x3, reqbuf
	mov w0, #1
	strb w0, [x3]
	strb w27, [x3, #1]
	mov w0, #8
	strh w0, [x3, #2]
	str w21, [x3, #4]
	str w25, [x3, #8]
	str wzr, [x3, #12]
	mov w0, #300
	strh w0, [x3, #16]
	mov w0, #340
	strh w0, [x3, #18]
	strh wzr, [x3, #20]
	mov w0, #1
	strh w0, [x3, #22]
	str w26, [x3, #24]
	str wzr, [x3, #28]
	mov x1, x3
	mov x2, #32
	bl send_all

	// MapWindow (opcode 8)
	laddr x3, reqbuf
	mov w0, #8
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #2
	strh w0, [x3, #2]
	str w21, [x3, #4]
	mov x1, x3
	mov x2, #8
	bl send_all

	// sleep 300ms
	laddr x0, ts300
	mov x1, #0
	mov x8, #101
	svc #0

	// nine CreateGC (opcode 55)
	mov w28, #0
gcloop:
	laddr x3, reqbuf
	mov w0, #55
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #5
	strh w0, [x3, #2]
	add w0, w20, w28
	add w0, w0, #2
	str w0, [x3, #4]
	str w21, [x3, #8]
	mov w0, #4
	str w0, [x3, #12]
	laddr x4, gc_colors
	ldr w0, [x4, w28, uxtw #2]
	str w0, [x3, #16]
	mov x1, x3
	mov x2, #20
	bl send_all
	add w28, w28, #1
	cmp w28, #9
	b.lt gcloop

	// build 256-entry fire palette (RGB ramps, matches spec table)
	laddr x3, pal_buf
	mov w4, #0
	mov w5, #3
	mov w6, #255
palloop:
	mul w0, w4, w5
	cmp w0, w6
	csel w0, w0, w6, lt
	strb w0, [x3], #1
	sub w0, w4, #85
	mul w0, w0, w5
	cmp w0, #0
	csel w0, w0, wzr, gt
	cmp w0, w6
	csel w0, w0, w6, lt
	strb w0, [x3], #1
	sub w0, w4, #170
	mul w0, w0, w5
	cmp w0, #0
	csel w0, w0, wzr, gt
	cmp w0, w6
	csel w0, w0, w6, lt
	strb w0, [x3], #1
	add w4, w4, #1
	cmp w4, #256
	b.lt palloop

	mov w22, #0                 // t

frame_loop:
	// 1. fire: pick current/next by t&1
	laddr x23, buf_a
	laddr x24, buf_b
	tst w22, #1
	b.eq 1f
	laddr x23, buf_b
	laddr x24, buf_a
1:
	// seed bottom row of next
	mov w9, #44700
	add x25, x24, x9
	mov w26, #0
seed_loop:
	bl rand_next
	and w0, w0, #63
	add w0, w0, #180
	strb w0, [x25, w26, uxtw]
	add w26, w26, #1
	cmp w26, #300
	b.lt seed_loop

	// propagate
	mov w25, #0                 // y
prop_y:
	mov w9, #300
	mul w26, w25, w9            // row offset
	add w27, w26, #300          // below-row offset
	mov w28, #0                 // x
prop_x:
	add w9, w27, w28
	ldrb w10, [x23, w9, uxtw]   // below
	sub w11, w28, #1
	cmp w28, #0
	mov w12, #299
	csel w11, w12, w11, eq
	add w11, w27, w11
	ldrb w11, [x23, w11, uxtw]  // left (wrap)
	add w13, w28, #1
	cmp w28, #299
	csel w13, wzr, w13, eq
	add w13, w27, w13
	ldrb w13, [x23, w13, uxtw]  // right (wrap)
	add w10, w10, w11
	add w10, w10, w13
	mov w11, #3
	udiv w10, w10, w11          // avg
	bl rand_next
	and w0, w0, #7
	add w0, w0, #4              // cooling
	subs w10, w10, w0
	csel w10, w10, wzr, ge
	add w9, w26, w28
	strb w10, [x24, w9, uxtw]
	add w28, w28, #1
	cmp w28, #300
	b.lt prop_x
	add w25, w25, #1
	cmp w25, #149
	b.lt prop_y

	// render next through palette
	laddr x9, pal_buf
	laddr x10, pix_buf
	mov w11, #0
	movz w12, #0xAFC8           // 45000
2:
	ldrb w13, [x24, w11, uxtw]
	add w14, w13, w13, lsl #1
	add x14, x9, w14, uxtw
	ldrb w15, [x14]             // R
	ldrb w16, [x14, #1]         // G
	ldrb w17, [x14, #2]         // B
	orr w17, w17, w16, lsl #8
	orr w17, w17, w15, lsl #16
	str w17, [x10], #4
	add w11, w11, #1
	cmp w11, w12
	b.lt 2b

	// PutImage (opcode 72): 24-byte header, then 180000-byte payload
	laddr x3, reqbuf
	mov w0, #72
	strb w0, [x3]
	mov w0, #2
	strb w0, [x3, #1]
	mov w0, #45006
	strh w0, [x3, #2]
	str w21, [x3, #4]
	add w0, w20, #3             // gc_putimg
	str w0, [x3, #8]
	mov w0, #300
	strh w0, [x3, #12]
	mov w0, #150
	strh w0, [x3, #14]
	strh wzr, [x3, #16]
	mov w0, #150
	strh w0, [x3, #18]
	strb wzr, [x3, #20]
	mov w0, #24
	strb w0, [x3, #21]
	strh wzr, [x3, #22]
	mov x1, x3
	mov x2, #24
	bl send_all
	laddr x1, pix_buf
	movz w2, #0xBF20            // 180000
	movk w2, #0x2, lsl #16
	bl send_all

	// 2. clear top half
	laddr x3, reqbuf
	mov w0, #70
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #5
	strh w0, [x3, #2]
	str w21, [x3, #4]
	add w0, w20, #2             // gc_black
	str w0, [x3, #8]
	strh wzr, [x3, #12]
	strh wzr, [x3, #14]
	mov w0, #300
	strh w0, [x3, #16]
	mov w0, #150
	strh w0, [x3, #18]
	mov x1, x3
	mov x2, #20
	bl send_all

	// 3. cube
	laddr x9, sine_table
	and w0, w22, #63
	add w1, w0, #16
	and w1, w1, #63
	ldrsb w25, [x9, w0, uxtw]   // sa
	ldrsb w26, [x9, w1, uxtw]   // ca
	lsl w0, w22, #1
	and w0, w0, #63
	add w1, w0, #16
	and w1, w1, #63
	ldrsb w27, [x9, w0, uxtw]   // sb
	ldrsb w28, [x9, w1, uxtw]   // cb

	laddr x10, verts
	laddr x11, vx_buf
	laddr x12, vy_buf
	laddr x13, vdepth
	mov w14, #0
vert_loop:
	ldrsb w0, [x10], #1         // x
	ldrsb w1, [x10], #1         // y
	ldrsb w2, [x10], #1         // z
	mul w3, w1, w26
	msub w3, w2, w25, w3
	asr w3, w3, #7              // y1
	mul w4, w1, w25
	madd w4, w2, w26, w4
	asr w4, w4, #7              // z1
	mul w5, w0, w28
	madd w5, w4, w27, w5
	asr w5, w5, #7              // x2
	mul w6, w4, w28
	msub w6, w0, w27, w6
	asr w6, w6, #7              // z2
	add w5, w5, #150
	add w3, w3, #150
	strh w5, [x11], #2
	strh w3, [x12], #2
	str w6, [x13], #4
	add w14, w14, #1
	cmp w14, #8
	b.lt vert_loop

	// per-face depth sums
	laddr x10, faces
	laddr x11, vdepth
	laddr x12, face_sort
	mov w13, #0
fd_loop:
	mov w14, wzr
	mov w15, #0
1:	ldrb w0, [x10], #1
	ldr w1, [x11, w0, uxtw #2]
	add w14, w14, w1
	add w15, w15, #1
	cmp w15, #4
	b.lt 1b
	add x10, x10, #1            // skip gc byte
	str w14, [x12], #4
	str w13, [x12], #4
	add w13, w13, #1
	cmp w13, #6
	b.lt fd_loop

	// bubble sort ascending by depth sum
	mov w13, #0
sort_outer:
	laddr x12, face_sort
	mov w14, #0
sort_inner:
	ldr w0, [x12]
	ldr w1, [x12, #8]
	cmp w0, w1
	b.le 2f
	ldr x2, [x12]
	ldr x3, [x12, #8]
	str x3, [x12]
	str x2, [x12, #8]
2:	add x12, x12, #8
	add w14, w14, #1
	cmp w14, #5
	b.lt sort_inner
	add w13, w13, #1
	cmp w13, #5
	b.lt sort_outer

	// FillPoly (opcode 69) faces, back-to-front
	mov w25, #0
face_draw:
	laddr x12, face_sort
	add x12, x12, w25, uxtw #3
	ldr w26, [x12, #4]          // face index
	laddr x10, faces
	mov w0, #5
	mul w0, w26, w0
	add x10, x10, w0, uxtw
	laddr x3, reqbuf
	mov w0, #69
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #8
	strh w0, [x3, #2]
	str w21, [x3, #4]
	ldrb w0, [x10, #4]
	add w0, w20, w0             // face gc
	str w0, [x3, #8]
	mov w0, #2
	strb w0, [x3, #12]          // Convex
	strb wzr, [x3, #13]         // CoordModeOrigin
	strh wzr, [x3, #14]
	laddr x11, vx_buf
	laddr x12, vy_buf
	add x4, x3, #16
	mov w5, #0
1:	ldrb w0, [x10, w5, uxtw]
	ldrh w1, [x11, w0, uxtw #1]
	ldrh w2, [x12, w0, uxtw #1]
	strh w1, [x4], #2
	strh w2, [x4], #2
	add w5, w5, #1
	cmp w5, #4
	b.lt 1b
	mov x1, x3
	mov x2, #32
	bl send_all
	add w25, w25, #1
	cmp w25, #6
	b.lt face_draw

	// 12 edges in one PolySegment (opcode 66)
	laddr x3, reqbuf
	mov w0, #66
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #27
	strh w0, [x3, #2]
	str w21, [x3, #4]
	add w0, w20, #2             // gc_black
	str w0, [x3, #8]
	laddr x10, edges
	laddr x11, vx_buf
	laddr x12, vy_buf
	add x4, x3, #12
	mov w5, #0
1:	ldrb w0, [x10], #1
	ldrh w1, [x11, w0, uxtw #1]
	ldrh w2, [x12, w0, uxtw #1]
	strh w1, [x4], #2
	strh w2, [x4], #2
	add w5, w5, #1
	cmp w5, #24
	b.lt 1b
	mov x1, x3
	mov x2, #108
	bl send_all

	// 4. scroller: clear band (0,300,300,40)
	laddr x3, reqbuf
	mov w0, #70
	strb w0, [x3]
	strb wzr, [x3, #1]
	mov w0, #5
	strh w0, [x3, #2]
	str w21, [x3, #4]
	add w0, w20, #2
	str w0, [x3, #8]
	strh wzr, [x3, #12]
	mov w0, #300
	strh w0, [x3, #14]
	strh w0, [x3, #16]
	mov w0, #40
	strh w0, [x3, #18]
	mov x1, x3
	mov x2, #20
	bl send_all

	// collect glyph rectangles into one PolyFillRectangle
	laddr x4, scr_buf
	add x4, x4, #12
	mov w25, #0                 // rect count
	mov w26, #0                 // char index
	lsl w27, w22, #2            // scroll_offset
scr_char:
	mov w0, #18
	mul w0, w26, w0
	sub w28, w0, w27            // char_x
	cmp w28, #300
	b.ge scr_next
	cmn w28, #15
	b.le scr_next
	laddr x9, message
	ldrb w0, [x9, w26, uxtw]
	laddr x9, font
	mov w1, #7
	mul w0, w0, w1
	add x9, x9, w0, uxtw
	mov w10, #0                 // row
2:	ldrb w11, [x9, w10, uxtw]
	mov w12, #0                 // col
3:	mov w13, #16
	lsr w13, w13, w12
	tst w11, w13
	b.eq 4f
	add w13, w12, w12, lsl #1
	add w13, w28, w13           // x
	add w14, w10, w10, lsl #1
	add w14, w14, #309          // y
	strh w13, [x4], #2
	strh w14, [x4], #2
	mov w15, #3
	strh w15, [x4], #2
	strh w15, [x4], #2
	add w25, w25, #1
4:	add w12, w12, #1
	cmp w12, #5
	b.lt 3b
	add w10, w10, #1
	cmp w10, #7
	b.lt 2b
scr_next:
	add w26, w26, #1
	cmp w26, #138
	b.lt scr_char
	cbz w25, scr_done
	laddr x3, scr_buf
	mov w0, #70
	strb w0, [x3]
	strb wzr, [x3, #1]
	add w0, w25, w25
	add w0, w0, #3
	strh w0, [x3, #2]
	str w21, [x3, #4]
	add w0, w20, #10            // gc_white
	str w0, [x3, #8]
	mov x1, x3
	mov w2, #12
	add w2, w2, w25, lsl #3
	bl send_all
scr_done:

	// 5. print frame=N
	laddr x3, numbuf
	laddr x9, frame_str
	mov w1, #0
1:	ldrb w0, [x9, w1, uxtw]
	strb w0, [x3, w1, uxtw]
	add w1, w1, #1
	cmp w1, #6
	b.lt 1b
	add x4, x3, #6
	mov w0, w22
	mov w5, #10
	mov w6, #0
	laddr x9, numbuf
	add x9, x9, #16
2:	udiv w1, w0, w5
	msub w2, w1, w5, w0
	add w2, w2, #48
	strb w2, [x9, w6, uxtw]
	add w6, w6, #1
	mov w0, w1
	cbnz w0, 2b
3:	sub w6, w6, #1
	ldrb w0, [x9, w6, uxtw]
	strb w0, [x4], #1
	cbnz w6, 3b
	mov w0, #10
	strb w0, [x4], #1
	laddr x1, numbuf
	sub x2, x4, x1
	mov x0, #1
	mov x8, #64
	svc #0

	// 6. sleep 80ms
	laddr x0, ts80
	mov x1, #0
	mov x8, #101
	svc #0

	// 7. next frame
	add w22, w22, #1
	cmp w22, #300
	b.lt frame_loop

	// final 2s, then exit
	laddr x0, ts2
	mov x1, #0
	mov x8, #101
	svc #0
	mov x0, #0
	mov x8, #94
	svc #0

fail:
	mov x0, #1
	mov x8, #94
	svc #0

// send_all(x1=buf, x2=len) on fd x19
send_all:
1:	mov x0, x19
	mov x8, #64
	svc #0
	cmp x0, #0
	b.le fail
	add x1, x1, x0
	subs x2, x2, x0
	b.gt 1b
	ret

// read_full(x1=buf, x2=len) on fd x19
read_full:
1:	mov x0, x19
	mov x8, #63
	svc #0
	cmp x0, #0
	b.le fail
	add x1, x1, x0
	subs x2, x2, x0
	b.gt 1b
	ret

// LCG: seed = seed*1103515245 + 12345, return seed>>16
rand_next:
	laddr x1, rand_seed
	ldr w0, [x1]
	movz w2, #0x4E6D
	movk w2, #0x41C6, lsl #16
	mul w0, w0, w2
	mov w3, #12345
	add w0, w0, w3
	str w0, [x1]
	lsr w0, w0, #16
	ret

	.data
	.balign 8
sockaddr:
	.byte 1, 0
	.ascii "/tmp/.X11-unix/X0"
	.byte 0
	.space 90

setup_req:
	.byte 0x6c, 0
	.byte 11, 0
	.byte 0, 0
	.byte 18, 0
	.byte 16, 0
	.byte 0, 0
	.ascii "MIT-MAGIC-COOKIE-1"
	.byte 0, 0
	.byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

sine_table:
	.byte 0, 12, 25, 37, 49, 60, 71, 81, 90, 98, 106, 112, 117, 122, 125, 126
	.byte 127, 126, 125, 122, 117, 112, 106, 98, 90, 81, 71, 60, 49, 37, 25, 12
	.byte 0, -12, -25, -37, -49, -60, -71, -81, -90, -98, -106, -112, -117, -122, -125, -126
	.byte -127, -126, -125, -122, -117, -112, -106, -98, -90, -81, -71, -60, -49, -37, -25, -12

verts:
	.byte -100, -100, -100
	.byte 100, -100, -100
	.byte 100, 100, -100
	.byte -100, 100, -100
	.byte -100, -100, 100
	.byte 100, -100, 100
	.byte 100, 100, 100
	.byte -100, 100, 100

faces:
	.byte 0, 1, 5, 4, 4
	.byte 3, 7, 6, 2, 5
	.byte 4, 5, 6, 7, 6
	.byte 1, 0, 3, 2, 7
	.byte 0, 4, 7, 3, 8
	.byte 5, 1, 2, 6, 9

edges:
	.byte 0, 1, 1, 2, 2, 3, 3, 0
	.byte 4, 5, 5, 6, 6, 7, 7, 4
	.byte 0, 4, 1, 5, 2, 6, 3, 7

font:
	.byte 14, 17, 17, 31, 17, 17, 17
	.byte 30, 17, 17, 30, 17, 17, 30
	.byte 15, 16, 16, 16, 16, 16, 15
	.byte 30, 17, 17, 17, 17, 17, 30
	.byte 31, 16, 16, 30, 16, 16, 31
	.byte 31, 16, 16, 30, 16, 16, 16
	.byte 15, 16, 16, 23, 17, 17, 15
	.byte 17, 17, 17, 31, 17, 17, 17
	.byte 31, 4, 4, 4, 4, 4, 31
	.byte 7, 2, 2, 2, 2, 18, 12
	.byte 17, 18, 20, 24, 20, 18, 17
	.byte 16, 16, 16, 16, 16, 16, 31
	.byte 17, 27, 21, 17, 17, 17, 17
	.byte 17, 25, 21, 19, 17, 17, 17
	.byte 14, 17, 17, 17, 17, 17, 14
	.byte 30, 17, 17, 30, 16, 16, 16
	.byte 14, 17, 17, 17, 21, 18, 13
	.byte 30, 17, 17, 30, 20, 18, 17
	.byte 15, 16, 16, 14, 1, 1, 30
	.byte 31, 4, 4, 4, 4, 4, 4
	.byte 17, 17, 17, 17, 17, 17, 14
	.byte 17, 17, 17, 17, 17, 10, 4
	.byte 17, 17, 17, 21, 21, 27, 17
	.byte 17, 17, 10, 4, 10, 17, 17
	.byte 17, 17, 10, 4, 4, 4, 4
	.byte 31, 1, 2, 4, 8, 16, 31
	.byte 14, 17, 19, 21, 25, 17, 14
	.byte 4, 12, 4, 4, 4, 4, 31
	.byte 14, 17, 1, 2, 4, 8, 31
	.byte 30, 1, 1, 14, 1, 1, 30
	.byte 2, 6, 10, 18, 31, 2, 2
	.byte 31, 16, 16, 30, 1, 1, 30
	.byte 14, 16, 16, 30, 17, 17, 14
	.byte 31, 1, 2, 4, 8, 16, 16
	.byte 14, 17, 17, 14, 17, 17, 14
	.byte 14, 17, 17, 15, 1, 1, 14
	.byte 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 31, 0, 0, 0
	.byte 0, 4, 0, 0, 0, 4, 0
	.byte 4, 4, 4, 4, 4, 0, 4
	.byte 17, 1, 2, 4, 8, 16, 17

message:
	.byte 6, 17, 4, 4, 19, 8, 13, 6, 18, 36
	.byte 19, 14, 36, 19, 7, 4, 36, 3, 4, 12
	.byte 14, 18, 2, 4, 13, 4, 36, 37, 36, 27
	.byte 26, 26, 40, 36, 7, 0, 13, 3, 36, 22
	.byte 17, 8, 19, 19, 4, 13, 36, 0, 0, 17
	.byte 2, 7, 32, 30, 36, 0, 18, 18, 4, 12
	.byte 1, 11, 24, 36, 37, 36, 25, 4, 17, 14
	.byte 36, 11, 8, 1, 2, 36, 25, 4, 17, 14
	.byte 36, 2, 14, 12, 15, 8, 11, 4, 17, 36
	.byte 37, 36, 2, 14, 3, 4, 3, 36, 21, 8
	.byte 0, 36, 0, 8, 36, 11, 14, 14, 15, 36
	.byte 4, 13, 6, 8, 13, 4, 4, 17, 8, 13
	.byte 6, 36, 37, 36, 2, 11, 0, 20, 3, 4
	.byte 36, 2, 14, 3, 4, 36, 37, 36

	.balign 4
gc_colors:
	.word 0x00000000
	.word 0x00000000
	.word 0x00FF0000
	.word 0x0000FFFF
	.word 0x0000FF00
	.word 0x00FF00FF
	.word 0x000000FF
	.word 0x00FFFF00
	.word 0x00FFFFFF

	.balign 4
rand_seed:
	.word 12345

	.balign 8
ts300:
	.quad 0
	.quad 300000000
ts80:
	.quad 0
	.quad 80000000
ts2:
	.quad 2
	.quad 0

wid_str:
	.ascii "window_id=0x"
frame_str:
	.ascii "frame="

	.bss
	.balign 8
reply_buf:
	.space 65536
buf_a:
	.space 45000
buf_b:
	.space 45000
	.balign 4
pix_buf:
	.space 180000
	.balign 8
reqbuf:
	.space 256
scr_buf:
	.space 8192
	.balign 8
face_sort:
	.space 48
vx_buf:
	.space 16
vy_buf:
	.space 16
	.balign 4
vdepth:
	.space 32
numbuf:
	.space 32
pal_buf:
	.space 768
