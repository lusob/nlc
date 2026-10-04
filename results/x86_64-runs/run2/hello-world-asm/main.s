.intel_syntax noprefix
.global _start
.section .text
_start:
    mov eax, 1
    mov edi, 1
    lea rsi, [rip + msg]
    mov edx, 14
    syscall
    mov eax, 231
    xor edi, edi
    syscall
.section .rodata
msg:
    .ascii "Hello, world!\n"
