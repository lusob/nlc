    .data
sockaddr:
    .hword  2
    .byte   0x1f, 0xbc
    .byte   127, 0, 0, 1
    .space  8
optval:
    .word   1
msg:
    .ascii  "Listening on port 8124\n"
msg_len = . - msg
resp:
    .ascii  "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC\n"
resp_len = . - resp

    .bss
buf:
    .space  512

    .text
    .global _start
_start:
    // socket(AF_INET, SOCK_STREAM, 0)
    mov     x0, #2
    mov     x1, #1
    mov     x2, #0
    mov     x8, #198
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0

    // setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &optval, 4)
    mov     x0, x19
    mov     x1, #1
    mov     x2, #2
    adrp    x3, optval
    add     x3, x3, :lo12:optval
    mov     x4, #4
    mov     x8, #208
    svc     #0

    // bind(fd, &sockaddr, 16)
    mov     x0, x19
    adrp    x1, sockaddr
    add     x1, x1, :lo12:sockaddr
    mov     x2, #16
    mov     x8, #200
    svc     #0
    cmp     x0, #0
    b.lt    fail

    // listen(fd, 16)
    mov     x0, x19
    mov     x1, #16
    mov     x8, #201
    svc     #0
    cmp     x0, #0
    b.lt    fail

    // write(1, msg, msg_len)
    mov     x0, #1
    adrp    x1, msg
    add     x1, x1, :lo12:msg
    mov     x2, #msg_len
    mov     x8, #64
    svc     #0

accept_loop:
    // accept(fd, NULL, NULL)
    mov     x0, x19
    mov     x1, #0
    mov     x2, #0
    mov     x8, #202
    svc     #0
    cmp     x0, #0
    b.lt    accept_loop
    mov     x20, x0

    // read(conn, buf, 512)
    mov     x0, x20
    adrp    x1, buf
    add     x1, x1, :lo12:buf
    mov     x2, #512
    mov     x8, #63
    svc     #0

    // write(conn, resp, resp_len)
    mov     x0, x20
    adrp    x1, resp
    add     x1, x1, :lo12:resp
    mov     x2, #resp_len
    mov     x8, #64
    svc     #0

    // close(conn)
    mov     x0, x20
    mov     x8, #57
    svc     #0
    b       accept_loop

fail:
    mov     x0, #1
    mov     x8, #94
    svc     #0
