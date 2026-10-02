	.text
	.global _start
_start:
	mov	x27, #0			// t = frame counter

frame_loop:
	// sa, ca, sb, cb from sine table
	adrp	x9, sine_table
	add	x9, x9, :lo12:sine_table
	and	x10, x27, #63		// angle_a
	ldrsb	w19, [x9, x10]		// sa
	add	x11, x10, #16
	and	x11, x11, #63
	ldrsb	w20, [x9, x11]		// ca
	lsl	x12, x27, #1
	and	x12, x12, #63		// angle_b
	ldrsb	w21, [x9, x12]		// sb
	add	x13, x12, #16
	and	x13, x13, #63
	ldrsb	w22, [x9, x13]		// cb

	// rotate + project the 8 vertices
	adrp	x9, verts
	add	x9, x9, :lo12:verts
	adrp	x25, proj
	add	x25, x25, :lo12:proj
	mov	x11, #0
vloop:
	add	x12, x11, x11, lsl #1	// i*3
	add	x12, x9, x12
	ldrsb	w0, [x12]		// x
	ldrsb	w1, [x12, #1]		// y
	ldrsb	w2, [x12, #2]		// z
	mul	w3, w1, w20
	msub	w3, w2, w19, w3		// y*ca - z*sa
	asr	w3, w3, #7		// y1
	mul	w4, w1, w19
	madd	w4, w2, w20, w4		// y*sa + z*ca
	asr	w4, w4, #7		// z1
	mul	w5, w0, w22
	madd	w5, w4, w21, w5		// x*cb + z1*sb
	asr	w5, w5, #7		// x2
	add	w5, w5, #30		// screen_col
	asr	w6, w3, #1
	add	w6, w6, #10		// screen_row
	add	x13, x25, x11, lsl #1
	strb	w5, [x13]
	strb	w6, [x13, #1]
	add	x11, x11, #1
	cmp	x11, #8
	b.lt	vloop

	// clear framebuffer to spaces, newline ending each row
	adrp	x28, fb
	add	x28, x28, :lo12:fb
	mov	x11, #1220
	mov	w12, #32
clr:
	sub	x11, x11, #1
	strb	w12, [x28, x11]
	cbnz	x11, clr
	mov	x11, #20
	mov	w12, #10
	add	x13, x28, #60
nl:
	strb	w12, [x13]
	add	x13, x13, #61
	subs	x11, x11, #1
	b.ne	nl

	// draw the 12 edges
	adrp	x24, edges
	add	x24, x24, :lo12:edges
	mov	x23, #0
edge_loop:
	add	x15, x24, x23, lsl #1
	ldrb	w0, [x15]
	ldrb	w2, [x15, #1]
	add	x16, x25, x0, lsl #1
	ldrsb	w0, [x16]		// x0
	ldrsb	w1, [x16, #1]		// y0
	add	x16, x25, x2, lsl #1
	ldrsb	w2, [x16]		// x1
	ldrsb	w3, [x16, #1]		// y1
	bl	draw_line
	add	x23, x23, #1
	cmp	x23, #12
	b.lt	edge_loop

	// write frame: ESC[2J prefix only on frame 0
	adrp	x1, outbuf
	add	x1, x1, :lo12:outbuf
	mov	x2, #1227
	cbz	x27, do_write
	add	x1, x1, #4
	mov	x2, #1223
do_write:
	mov	x0, #1
	mov	x8, #64
	svc	#0

	// nanosleep 50ms
	adrp	x0, ts
	add	x0, x0, :lo12:ts
	mov	x1, #0
	mov	x8, #101
	svc	#0

	add	x27, x27, #1
	cmp	x27, #64
	b.lt	frame_loop

	mov	x0, #0
	mov	x8, #94			// exit_group
	svc	#0

// Bresenham: w0=x0 w1=y0 w2=x1 w3=y1, fb base in x28
draw_line:
	subs	w4, w2, w0
	cneg	w4, w4, mi		// dx = abs(x1-x0)
	mov	w5, #1
	cneg	w5, w5, lt		// sx
	subs	w6, w3, w1
	cneg	w6, w6, mi
	mov	w7, #1
	cneg	w7, w7, lt		// sy
	neg	w6, w6			// dy = -abs(y1-y0)
	add	w8, w4, w6		// err = dx + dy
	mov	w16, #61
	mov	w17, #35		// '#'
dl_loop:
	cmp	w0, #60
	b.hs	dl_skip			// unsigned check also rejects x < 0
	cmp	w1, #20
	b.hs	dl_skip
	madd	w15, w1, w16, w0	// y*61 + x
	strb	w17, [x28, w15, sxtw]
dl_skip:
	cmp	w0, w2
	ccmp	w1, w3, #0, eq
	b.eq	dl_done
	lsl	w15, w8, #1		// e2 = 2*err
	cmp	w15, w6
	b.lt	dl_no_x
	add	w8, w8, w6
	add	w0, w0, w5
dl_no_x:
	cmp	w15, w4
	b.gt	dl_loop
	add	w8, w8, w4
	add	w1, w1, w7
	b	dl_loop
dl_done:
	ret

	.data
sine_table:
	.byte	0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126
	.byte	127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12
	.byte	0,-12,-25,-37,-49,-60,-71,-81,-90,-98,-106,-112,-117,-122,-125,-126
	.byte	-127,-126,-125,-122,-117,-112,-106,-98,-90,-81,-71,-60,-49,-37,-25,-12
verts:
	.byte	-15,-15,-15,  15,-15,-15,  15,15,-15,  -15,15,-15
	.byte	-15,-15, 15,  15,-15, 15,  15,15, 15,  -15,15, 15
edges:
	.byte	0,1, 1,2, 2,3, 3,0
	.byte	4,5, 5,6, 6,7, 7,4
	.byte	0,4, 1,5, 2,6, 3,7
outbuf:
	.byte	0x1b,0x5b,0x32,0x4a	// ESC[2J
	.byte	0x1b,0x5b,0x48		// ESC[H
fb:
	.skip	1220			// 20 rows * (60 chars + '\n')
	.balign	8
ts:
	.quad	0
	.quad	50000000

	.bss
	.balign	4
proj:
	.skip	16			// 8 x (col,row) signed bytes
