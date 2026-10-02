.intel_syntax noprefix
.global _start

.section .rodata
msg:
    .ascii "Hello, world!\n"
    .set len, . - msg

.text
_start:
    mov eax, 1
    mov edi, 1
    lea rsi, [rip + msg]
    mov edx, len
    syscall
    mov eax, 231
    xor edi, edi
    syscall
