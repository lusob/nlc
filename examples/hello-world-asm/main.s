.section .rodata
msg:
    .ascii "Hello, world!\n"
msg_len = . - msg

.section .text
.global _start
_start:
    mov x0, #1
    ldr x1, =msg
    mov x2, #msg_len
    mov x8, #64
    svc #0

    mov x0, #0
    mov x8, #94
    svc #0
