.intel_syntax noprefix
.global _start

.section .data
addr:
    .byte 2,0,0x1f,0xbc,127,0,0,1
    .quad 0
msg:
    .ascii "Listening on port 8124\n"
.set msglen, . - msg
resp:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC\n"
.set resplen, . - resp
one:
    .long 1

.section .bss
buf:
    .skip 1024

.section .text
_start:
    mov eax, 41
    mov edi, 2
    mov esi, 1
    xor edx, edx
    syscall
    test rax, rax
    js fail
    mov r12, rax

    mov eax, 54
    mov rdi, r12
    mov esi, 1
    mov edx, 2
    lea r10, [rip+one]
    mov r8d, 4
    syscall

    mov eax, 49
    mov rdi, r12
    lea rsi, [rip+addr]
    mov edx, 16
    syscall
    test rax, rax
    js fail

    mov eax, 50
    mov rdi, r12
    mov esi, 16
    syscall
    test rax, rax
    js fail

    mov eax, 1
    mov edi, 1
    lea rsi, [rip+msg]
    mov edx, msglen
    syscall

loop:
    mov eax, 43
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js loop
    mov r13, rax

    xor eax, eax
    mov rdi, r13
    lea rsi, [rip+buf]
    mov edx, 1024
    syscall

    mov eax, 1
    mov rdi, r13
    lea rsi, [rip+resp]
    mov edx, resplen
    syscall

    mov eax, 3
    mov rdi, r13
    syscall
    jmp loop

fail:
    mov eax, 231
    mov edi, 1
    syscall
