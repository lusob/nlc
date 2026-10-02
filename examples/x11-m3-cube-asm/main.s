	.text
	.global _start

_start:
	// socket(AF_UNIX, SOCK_STREAM, 0)
	mov	x8, #198
	mov	x0, #1
	mov	x1, #1
	mov	x2, #0
	svc	#0
	cmp	x0, #0
	b.lt	fail
	mov	x19, x0

	// connect(fd, &saddr, 110)
	mov	x8, #203
	mov	x0, x19
	adrp	x1, saddr
	add	x1, x1, :lo12:saddr
	mov	x2, #110
	svc	#0
	cbnz	x0, fail

	// write setup request (48 bytes)
	mov	x8, #64
	mov	x0, x19
	adrp	x1, setupreq
	add	x1, x1, :lo12:setupreq
	mov	x2, #48
	svc	#0

	// read 8-byte reply header
	adrp	x9, buf
	add	x9, x9, :lo12:buf
	mov	x23, #0
rd8:
	mov	x8, #63
	mov	x0, x19
	add	x1, x9, x23
	mov	x2, #8
	sub	x2, x2, x23
	svc	#0
	cmp	x0, #0
	b.le	fail
	add	x23, x23, x0
	cmp	x23, #8
	b.lt	rd8

	// read addl_len*4 more bytes
	ldrh	w24, [x9, #6]
	lsl	x24, x24, #2
	add	x24, x24, #8
rdmore:
	cmp	x23, x24
	b.ge	parse
	mov	x8, #63
	mov	x0, x19
	add	x1, x9, x23
	sub	x2, x24, x23
	svc	#0
	cmp	x0, #0
	b.le	fail
	add	x23, x23, x0
	b	rdmore

parse:
	ldrb	w0, [x9]
	cmp	w0, #1
	b.ne	fail
	ldr	w22, [x9, #12]		// resource_id_base
	ldrh	w1, [x9, #24]		// vendor_len
	ldrb	w2, [x9, #29]		// num_formats
	add	w1, w1, #3
	and	w1, w1, #-4
	add	w3, w1, w2, lsl #3
	add	w3, w3, #40
	add	x10, x9, w3, uxtw
	ldr	w25, [x10]		// root_window
	ldr	w26, [x10, #32]		// root_visual
	ldrb	w27, [x10, #38]		// root_depth

	orr	w20, w22, #1		// window_id

	// print window_id=0x........
	adrp	x1, widmsg
	add	x1, x1, :lo12:widmsg
	add	x2, x1, #12
	mov	w4, #28
hexl:
	lsr	w5, w20, w4
	and	w5, w5, #15
	cmp	w5, #10
	add	w6, w5, #48
	add	w7, w5, #87
	csel	w5, w6, w7, lt
	strb	w5, [x2], #1
	subs	w4, w4, #4
	b.ge	hexl
	mov	x8, #64
	mov	x0, #1
	mov	x2, #21
	svc	#0

	// CreateWindow
	adrp	x1, cwreq
	add	x1, x1, :lo12:cwreq
	mov	w0, #1
	strb	w0, [x1]
	strb	w27, [x1, #1]
	mov	w0, #8
	strh	w0, [x1, #2]
	str	w20, [x1, #4]
	str	w25, [x1, #8]
	str	wzr, [x1, #12]
	mov	w0, #300
	strh	w0, [x1, #16]
	strh	w0, [x1, #18]
	strh	wzr, [x1, #20]
	mov	w0, #1
	strh	w0, [x1, #22]
	str	w26, [x1, #24]
	str	wzr, [x1, #28]
	mov	x8, #64
	mov	x0, x19
	mov	x2, #32
	svc	#0

	// MapWindow
	adrp	x1, mapreq
	add	x1, x1, :lo12:mapreq
	mov	w0, #8
	strb	w0, [x1]
	strb	wzr, [x1, #1]
	mov	w0, #2
	strh	w0, [x1, #2]
	str	w20, [x1, #4]
	mov	x8, #64
	mov	x0, x19
	mov	x2, #8
	svc	#0

	// sleep 300ms
	mov	x0, #0
	mov	x1, #0xa300
	movk	x1, #0x11e1, lsl #16
	bl	dosleep

	// CreateGC black and white
	orr	w0, w22, #2
	mov	w1, #0
	bl	mkgc
	orr	w0, w22, #3
	mov	w1, #0xffffff
	bl	mkgc

	// build PolyFillRectangle request once
	adrp	x1, fillreq
	add	x1, x1, :lo12:fillreq
	mov	w0, #70
	strb	w0, [x1]
	strb	wzr, [x1, #1]
	mov	w0, #5
	strh	w0, [x1, #2]
	str	w20, [x1, #4]
	orr	w0, w22, #2
	str	w0, [x1, #8]
	str	wzr, [x1, #12]
	mov	w0, #300
	strh	w0, [x1, #16]
	strh	w0, [x1, #18]

	// build PolySegment header once (length 3+12*2=27 units, 108 bytes)
	adrp	x1, segreq
	add	x1, x1, :lo12:segreq
	mov	w0, #66
	strb	w0, [x1]
	strb	wzr, [x1, #1]
	mov	w0, #27
	strh	w0, [x1, #2]
	str	w20, [x1, #4]
	orr	w0, w22, #3
	str	w0, [x1, #8]

	mov	w21, #0			// t

frame_loop:
	and	w0, w21, #63		// angle_a
	lsl	w1, w21, #1
	and	w1, w1, #63		// angle_b
	adrp	x9, sine
	add	x9, x9, :lo12:sine
	ldrsb	w2, [x9, w0, uxtw]	// sa
	add	w3, w0, #16
	and	w3, w3, #63
	ldrsb	w3, [x9, w3, uxtw]	// ca
	ldrsb	w4, [x9, w1, uxtw]	// sb
	add	w5, w1, #16
	and	w5, w5, #63
	ldrsb	w5, [x9, w5, uxtw]	// cb

	adrp	x10, verts
	add	x10, x10, :lo12:verts
	adrp	x11, proj
	add	x11, x11, :lo12:proj
	mov	w12, #8
vloop:
	ldrsb	w6, [x10], #1		// x
	ldrsb	w7, [x10], #1		// y
	ldrsb	w13, [x10], #1		// z
	mul	w14, w7, w3
	msub	w14, w13, w2, w14
	asr	w14, w14, #7		// y1
	mul	w15, w7, w2
	madd	w15, w13, w3, w15
	asr	w15, w15, #7		// z1
	mul	w16, w6, w5
	madd	w16, w15, w4, w16
	asr	w16, w16, #7		// x2
	add	w16, w16, #150
	add	w14, w14, #150
	strh	w16, [x11], #2
	strh	w14, [x11], #2
	subs	w12, w12, #1
	b.ne	vloop

	// fill 12 segments from edge list
	adrp	x10, edges
	add	x10, x10, :lo12:edges
	adrp	x11, proj
	add	x11, x11, :lo12:proj
	adrp	x12, segreq
	add	x12, x12, :lo12:segreq
	add	x12, x12, #12
	mov	w13, #12
eloop:
	ldrb	w0, [x10], #1
	ldrb	w1, [x10], #1
	ldr	w6, [x11, w0, uxtw #2]
	ldr	w7, [x11, w1, uxtw #2]
	str	w6, [x12], #4
	str	w7, [x12], #4
	subs	w13, w13, #1
	b.ne	eloop

	// clear window
	mov	x8, #64
	mov	x0, x19
	adrp	x1, fillreq
	add	x1, x1, :lo12:fillreq
	mov	x2, #20
	svc	#0

	// draw cube
	mov	x8, #64
	mov	x0, x19
	adrp	x1, segreq
	add	x1, x1, :lo12:segreq
	mov	x2, #108
	svc	#0

	// print frame=N
	adrp	x1, frmsg
	add	x1, x1, :lo12:frmsg
	cmp	w21, #10
	b.lt	onedig
	mov	w2, #10
	udiv	w3, w21, w2
	msub	w4, w3, w2, w21
	add	w3, w3, #48
	add	w4, w4, #48
	strb	w3, [x1, #6]
	strb	w4, [x1, #7]
	mov	w0, #10
	strb	w0, [x1, #8]
	mov	x2, #9
	b	doprint
onedig:
	add	w3, w21, #48
	strb	w3, [x1, #6]
	mov	w0, #10
	strb	w0, [x1, #7]
	mov	x2, #8
doprint:
	mov	x8, #64
	mov	x0, #1
	svc	#0

	// sleep 80ms
	mov	x0, #0
	mov	x1, #0xb400
	movk	x1, #0x04c4, lsl #16
	bl	dosleep

	add	w21, w21, #1
	cmp	w21, #64
	b.lt	frame_loop

	// keep final frame 2s, then exit
	mov	x0, #2
	mov	x1, #0
	bl	dosleep
	mov	x8, #94
	mov	x0, #0
	svc	#0

fail:
	mov	x8, #94
	mov	x0, #1
	svc	#0

// dosleep: x0=sec x1=nsec
dosleep:
	adrp	x2, ts
	add	x2, x2, :lo12:ts
	stp	x0, x1, [x2]
	mov	x0, x2
	mov	x1, #0
	mov	x8, #101
	svc	#0
	ret

// mkgc: w0=cid w1=foreground
mkgc:
	adrp	x2, gcreq
	add	x2, x2, :lo12:gcreq
	mov	w3, #55
	strb	w3, [x2]
	strb	wzr, [x2, #1]
	mov	w3, #5
	strh	w3, [x2, #2]
	str	w0, [x2, #4]
	str	w20, [x2, #8]
	mov	w3, #4
	str	w3, [x2, #12]
	str	w1, [x2, #16]
	mov	x8, #64
	mov	x0, x19
	mov	x1, x2
	mov	x2, #20
	svc	#0
	ret

	.data
	.balign	4
saddr:
	.hword	1
	.ascii	"/tmp/.X11-unix/X0"
	.byte	0
	.space	90

	.balign	4
setupreq:
	.byte	0x6c, 0
	.hword	11, 0, 18, 16, 0
	.ascii	"MIT-MAGIC-COOKIE-1"
	.byte	0, 0
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

sine:
	.byte	0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126
	.byte	127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12
	.byte	0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126
	.byte	-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12

verts:
	.byte	-100,-100,-100, 100,-100,-100, 100,100,-100, -100,100,-100
	.byte	-100,-100,100,  100,-100,100,  100,100,100,  -100,100,100

edges:
	.byte	0,1, 1,2, 2,3, 3,0, 4,5, 5,6, 6,7, 7,4, 0,4, 1,5, 2,6, 3,7

widmsg:
	.ascii	"window_id=0x00000000\n"
frmsg:
	.ascii	"frame=    "

	.bss
	.balign	8
ts:	.space	16
proj:	.space	32
cwreq:	.space	32
mapreq:	.space	8
gcreq:	.space	20
fillreq:
	.space	20
segreq:	.space	108
buf:	.space	32768
