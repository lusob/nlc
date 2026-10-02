.intel_syntax noprefix
.global _start

.data
addr:
    .short 1
    .ascii "/tmp/.X11-unix/X0"
    .zero 91
req:
    .byte 0x6c, 0
    .short 11, 0, 18, 16, 0
    .ascii "MIT-MAGIC-COOKIE-1"
    .byte 0, 0
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
out:
    .ascii "root_window=0x00000000\nroot_visual=0x00000000\n"
failmsg:
    .ascii "AUTH FAILED\n"

.bss
.lcomm buf, 16384

.text
_start:
    mov eax, 41
    mov edi, 1
    mov esi, 1
    xor edx, edx
    syscall
    test rax, rax
    js err
    mov r12, rax

    mov eax, 42
    mov rdi, r12
    lea rsi, [rip+addr]
    mov edx, 110
    syscall
    test rax, rax
    js err

    lea rsi, [rip+req]
    mov edx, 48
1:
    mov eax, 1
    mov rdi, r12
    syscall
    test rax, rax
    jle err
    add rsi, rax
    sub rdx, rax
    jnz 1b

    lea rsi, [rip+buf]
    mov edx, 8
    call readfull

    lea rbx, [rip+buf]
    cmp byte ptr [rbx], 1
    jne authfail

    movzx edx, word ptr [rbx+6]
    shl edx, 2
    lea rsi, [rbx+8]
    call readfull

    movzx eax, word ptr [rbx+24]
    add eax, 3
    and eax, -4
    add eax, 40
    movzx ecx, byte ptr [rbx+29]
    lea eax, [rax+rcx*8]
    mov r13d, dword ptr [rbx+rax]
    mov r14d, dword ptr [rbx+rax+32]

    lea rsi, [rip+out+14]
    mov edi, r13d
    call hex8
    lea rsi, [rip+out+37]
    mov edi, r14d
    call hex8

    mov eax, 1
    mov edi, 1
    lea rsi, [rip+out]
    mov edx, 46
    syscall
    mov eax, 231
    xor edi, edi
    syscall

authfail:
    mov eax, 1
    mov edi, 1
    lea rsi, [rip+failmsg]
    mov edx, 12
    syscall
err:
    mov eax, 231
    mov edi, 1
    syscall

readfull:
    test rdx, rdx
    jz 2f
    xor eax, eax
    mov rdi, r12
    syscall
    test rax, rax
    jle err
    add rsi, rax
    sub rdx, rax
    jmp readfull
2:
    ret

hex8:
    mov ecx, 8
3:
    rol edi, 4
    mov eax, edi
    and eax, 15
    add al, 48
    cmp al, 57
    jbe 4f
    add al, 39
4:
    mov [rsi], al
    inc rsi
    dec ecx
    jnz 3b
    ret
