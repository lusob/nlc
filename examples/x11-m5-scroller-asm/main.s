	.text
	.global _start

_start:
	// socket(AF_UNIX, SOCK_STREAM, 0)
	mov	x0, #1
	mov	x1, #1
	mov	x2, #0
	mov	x8, #198
	svc	#0
	cmp	x0, #0
	b.lt	fail
	mov	x19, x0

	// connect
	mov	x0, x19
	adrp	x1, sockaddr
	add	x1, x1, :lo12:sockaddr
	mov	x2, #110
	mov	x8, #203
	svc	#0
	cmp	x0, #0
	b.ne	fail

	// send setup request
	mov	x0, x19
	adrp	x1, setup
	add	x1, x1, :lo12:setup
	mov	x2, #48
	bl	write_all

	// read 8-byte header then body
	adrp	x28, xbuf
	add	x28, x28, :lo12:xbuf
	mov	x0, x19
	mov	x1, x28
	mov	x2, #8
	bl	read_n
	ldrh	w2, [x28, #6]
	lsl	x2, x2, #2
	mov	x0, x19
	add	x1, x28, #8
	bl	read_n
	ldrb	w0, [x28]
	cmp	w0, #1
	b.ne	fail

	// parse setup reply
	ldr	w24, [x28, #12]		// resource_id_base
	ldrh	w0, [x28, #24]		// vendor_len
	ldrb	w1, [x28, #29]		// num_formats
	add	w0, w0, #3
	and	w0, w0, #0xFFFFFFFC
	add	w0, w0, #40
	add	w0, w0, w1, lsl #3
	add	x2, x28, w0, uxtw
	ldr	w25, [x2]		// root window
	ldr	w26, [x2, #32]		// root visual
	ldrb	w27, [x2, #38]		// root depth

	orr	w20, w24, #1		// window_id
	orr	w21, w24, #2		// gc_black
	orr	w22, w24, #3		// gc_white

	mov	w0, w20
	bl	print_wid

	// CreateWindow
	adrp	x5, reqbuf
	add	x5, x5, :lo12:reqbuf
	mov	w0, #1
	strb	w0, [x5]
	strb	w27, [x5, #1]
	mov	w0, #8
	strh	w0, [x5, #2]
	str	w20, [x5, #4]
	str	w25, [x5, #8]
	strh	wzr, [x5, #12]
	strh	wzr, [x5, #14]
	mov	w0, #300
	strh	w0, [x5, #16]
	mov	w0, #40
	strh	w0, [x5, #18]
	strh	wzr, [x5, #20]
	mov	w0, #1
	strh	w0, [x5, #22]
	str	w26, [x5, #24]
	str	wzr, [x5, #28]
	mov	x0, x19
	mov	x1, x5
	mov	x2, #32
	bl	write_all

	// MapWindow
	adrp	x5, reqbuf
	add	x5, x5, :lo12:reqbuf
	mov	w0, #8
	strb	w0, [x5]
	strb	wzr, [x5, #1]
	mov	w0, #2
	strh	w0, [x5, #2]
	str	w20, [x5, #4]
	mov	x0, x19
	mov	x1, x5
	mov	x2, #8
	bl	write_all

	// sleep 300ms
	mov	x0, #0
	movz	x1, #0xA300
	movk	x1, #0x11E1, lsl #16
	bl	do_sleep

	// two GCs
	mov	w0, w21
	mov	w1, #0
	bl	make_gc
	mov	w0, w22
	movz	w1, #0xFFFF
	movk	w1, #0x00FF, lsl #16
	bl	make_gc

	mov	x23, #0			// t
frame_loop:
	// clear window (PolyFillRectangle, gc_black, full rect)
	adrp	x5, reqbuf
	add	x5, x5, :lo12:reqbuf
	mov	w0, #70
	strb	w0, [x5]
	strb	wzr, [x5, #1]
	mov	w0, #5
	strh	w0, [x5, #2]
	str	w20, [x5, #4]
	str	w21, [x5, #8]
	strh	wzr, [x5, #12]
	strh	wzr, [x5, #14]
	mov	w0, #300
	strh	w0, [x5, #16]
	mov	w0, #40
	strh	w0, [x5, #18]
	mov	x0, x19
	mov	x1, x5
	mov	x2, #20
	bl	write_all

	// build one PolyFillRectangle with all visible pixel blocks
	adrp	x5, reqbuf
	add	x5, x5, :lo12:reqbuf
	mov	w0, #70
	strb	w0, [x5]
	strb	wzr, [x5, #1]
	str	w20, [x5, #4]
	str	w22, [x5, #8]
	add	x6, x5, #12		// rect write ptr
	mov	x7, #0			// rect count
	lsl	w9, w23, #2		// scroll_offset = t*4
	mov	x10, #0			// i
char_loop:
	mov	w11, #18
	mul	w11, w10, w11
	sub	w11, w11, w9		// char_x
	add	w12, w11, #15
	tbnz	w12, #31, next_char	// char_x+15 < 0
	cmp	w11, #300
	b.ge	next_char
	adrp	x12, message
	add	x12, x12, :lo12:message
	ldrb	w13, [x12, x10]
	lsl	w14, w13, #3
	sub	w13, w14, w13		// glyph*7
	adrp	x12, font
	add	x12, x12, :lo12:font
	add	x12, x12, w13, uxtw
	mov	x14, #0			// row
row_loop:
	ldrb	w15, [x12, x14]
	mov	x16, #0			// col
col_loop:
	mov	w17, #4
	sub	w17, w17, w16
	lsr	w17, w15, w17
	tbz	w17, #0, no_pixel
	add	w2, w16, w16, lsl #1	// col*3
	add	w2, w2, w11
	strh	w2, [x6]
	add	w3, w14, w14, lsl #1	// row*3
	add	w3, w3, #9
	strh	w3, [x6, #2]
	mov	w4, #3
	strh	w4, [x6, #4]
	strh	w4, [x6, #6]
	add	x6, x6, #8
	add	x7, x7, #1
no_pixel:
	add	x16, x16, #1
	cmp	x16, #5
	b.lt	col_loop
	add	x14, x14, #1
	cmp	x14, #7
	b.lt	row_loop
next_char:
	add	x10, x10, #1
	cmp	x10, #138
	b.lt	char_loop

	lsl	w0, w7, #1
	add	w0, w0, #3		// length = 3 + 2*num_rects
	strh	w0, [x5, #2]
	lsl	x2, x7, #3
	add	x2, x2, #12
	mov	x0, x19
	mov	x1, x5
	bl	write_all

	mov	w0, w23
	bl	print_frame

	// sleep 80ms
	mov	x0, #0
	movz	x1, #0xB400
	movk	x1, #0x04C4, lsl #16
	bl	do_sleep

	add	x23, x23, #1
	cmp	x23, #150
	b.lt	frame_loop

	mov	x0, #1
	mov	x1, #0
	bl	do_sleep
	mov	x0, #0
	mov	x8, #94
	svc	#0

fail:
	mov	x0, #1
	mov	x8, #94
	svc	#0

// x0=fd x1=buf x2=len
write_all:
	mov	x3, x0
1:	cbz	x2, 2f
	mov	x0, x3
	mov	x8, #64
	svc	#0
	cmp	x0, #0
	b.le	2f
	add	x1, x1, x0
	sub	x2, x2, x0
	b	1b
2:	ret

// x0=fd x1=buf x2=n (exact)
read_n:
	mov	x3, x0
1:	cbz	x2, 2f
	mov	x0, x3
	mov	x8, #63
	svc	#0
	cmp	x0, #0
	b.le	fail
	add	x1, x1, x0
	sub	x2, x2, x0
	b	1b
2:	ret

// w0=cid w1=foreground
make_gc:
	stp	x29, x30, [sp, #-16]!
	adrp	x5, reqbuf
	add	x5, x5, :lo12:reqbuf
	mov	w2, #55
	strb	w2, [x5]
	strb	wzr, [x5, #1]
	mov	w2, #5
	strh	w2, [x5, #2]
	str	w0, [x5, #4]
	str	w20, [x5, #8]
	mov	w2, #4
	str	w2, [x5, #12]
	str	w1, [x5, #16]
	mov	x0, x19
	mov	x1, x5
	mov	x2, #20
	bl	write_all
	ldp	x29, x30, [sp], #16
	ret

// w0=value: print "frame=N\n"
print_frame:
	stp	x29, x30, [sp, #-32]!
	add	x9, sp, #16
	mov	w3, #10
	mov	x4, #0
1:	udiv	w5, w0, w3
	msub	w6, w5, w3, w0
	add	w6, w6, #48
	strb	w6, [x9, x4]
	add	x4, x4, #1
	mov	w0, w5
	cbnz	w0, 1b
	adrp	x7, digits
	add	x7, x7, :lo12:digits
2:	sub	x4, x4, #1
	ldrb	w6, [x9, x4]
	strb	w6, [x7], #1
	cbnz	x4, 2b
	mov	w6, #10
	strb	w6, [x7], #1
	adrp	x1, framestr
	add	x1, x1, :lo12:framestr
	sub	x2, x7, x1
	mov	x0, #1
	bl	write_all
	ldp	x29, x30, [sp], #32
	ret

// w0=id: print "window_id=0xXXXXXXXX\n"
print_wid:
	stp	x29, x30, [sp, #-16]!
	adrp	x4, widdig
	add	x4, x4, :lo12:widdig
	mov	w2, #28
1:	lsr	w3, w0, w2
	and	w3, w3, #15
	cmp	w3, #10
	b.lt	2f
	add	w3, w3, #87
	b	3f
2:	add	w3, w3, #48
3:	strb	w3, [x4], #1
	subs	w2, w2, #4
	b.ge	1b
	mov	w3, #10
	strb	w3, [x4]
	mov	x0, #1
	adrp	x1, widstr
	add	x1, x1, :lo12:widstr
	mov	x2, #21
	bl	write_all
	ldp	x29, x30, [sp], #16
	ret

// x0=sec x1=nsec
do_sleep:
	adrp	x2, ts
	add	x2, x2, :lo12:ts
	stp	x0, x1, [x2]
	mov	x0, x2
	mov	x1, #0
	mov	x8, #101
	svc	#0
	ret

	.data
sockaddr:
	.hword	1
	.ascii	"/tmp/.X11-unix/X0"
	.skip	91

setup:
	.byte	0x6c, 0
	.hword	11, 0, 18, 16, 0
	.ascii	"MIT-MAGIC-COOKIE-1"
	.byte	0, 0
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

font:
	.byte	14,17,17,31,17,17,17
	.byte	30,17,17,30,17,17,30
	.byte	15,16,16,16,16,16,15
	.byte	30,17,17,17,17,17,30
	.byte	31,16,16,30,16,16,31
	.byte	31,16,16,30,16,16,16
	.byte	15,16,16,23,17,17,15
	.byte	17,17,17,31,17,17,17
	.byte	31,4,4,4,4,4,31
	.byte	7,2,2,2,2,18,12
	.byte	17,18,20,24,20,18,17
	.byte	16,16,16,16,16,16,31
	.byte	17,27,21,17,17,17,17
	.byte	17,25,21,19,17,17,17
	.byte	14,17,17,17,17,17,14
	.byte	30,17,17,30,16,16,16
	.byte	14,17,17,17,21,18,13
	.byte	30,17,17,30,20,18,17
	.byte	15,16,16,14,1,1,30
	.byte	31,4,4,4,4,4,4
	.byte	17,17,17,17,17,17,14
	.byte	17,17,17,17,17,10,4
	.byte	17,17,17,21,21,27,17
	.byte	17,17,10,4,10,17,17
	.byte	17,17,10,4,4,4,4
	.byte	31,1,2,4,8,16,31
	.byte	14,17,19,21,25,17,14
	.byte	4,12,4,4,4,4,31
	.byte	14,17,1,2,4,8,31
	.byte	30,1,1,14,1,1,30
	.byte	2,6,10,18,31,2,2
	.byte	31,16,16,30,1,1,30
	.byte	14,16,16,30,17,17,14
	.byte	31,1,2,4,8,16,16
	.byte	14,17,17,14,17,17,14
	.byte	14,17,17,15,1,1,14
	.byte	0,0,0,0,0,0,0
	.byte	0,0,0,31,0,0,0
	.byte	0,4,0,0,0,4,0
	.byte	4,4,4,4,4,0,4
	.byte	17,1,2,4,8,16,17

message:
	.byte	6,17,4,4,19,8,13,6,18,36,19,14,36,19,7,4,36,3,4,12
	.byte	14,18,2,4,13,4,36,37,36,27,26,26,40,36,7,0,13,3,36,22
	.byte	17,8,19,19,4,13,36,0,0,17,2,7,32,30,36,0,18,18,4,12
	.byte	1,11,24,36,37,36,25,4,17,14,36,11,8,1,2,36,25,4,17,14
	.byte	36,2,14,12,15,8,11,4,17,36,37,36,2,14,3,4,3,36,21,8
	.byte	0,36,0,8,36,11,14,14,15,36,4,13,6,8,13,4,4,17,8,13
	.byte	6,36,37,36,2,11,0,20,3,4,36,2,14,3,4,36,37,36

framestr:
	.ascii	"frame="
digits:
	.skip	8
widstr:
	.ascii	"window_id=0x"
widdig:
	.skip	12

	.bss
	.balign	8
xbuf:
	.skip	32768
reqbuf:
	.skip	8192
ts:
	.skip	16
