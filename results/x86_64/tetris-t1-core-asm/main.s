.intel_syntax noprefix
.global _start
.text
_start:
    mov ebp, offset state
    mov r15d, offset req
    mov dword ptr [rbp], 12345
    push 1
    pop rdi
    push 1
    pop rsi
    xor edx, edx
    push 41
    pop rax
    syscall
    mov ebx, eax
    mov edi, ebx
    mov esi, offset sock
    push 110
    pop rdx
    push 42
    pop rax
    syscall
    mov esi, offset setup
    push 48
    pop rdx
    call send
    mov r13d, offset buf
    mov rsi, r13
    push 8
    pop rdx
    call readn
    cmp byte ptr [r13], 1
    jne fail
    movzx edx, word ptr [r13+6]
    shl edx, 2
    lea rsi, [r13+8]
    call readn
    mov r12d, [r13+12]
    movzx eax, word ptr [r13+24]
    add eax, 3
    and eax, -4
    movzx ecx, byte ptr [r13+29]
    lea eax, [rax+rcx*8+40]
    add r13, rax
    mov esi, offset s_wid
    call cpy
    lea eax, [r12+1]
    push 8
    pop rcx
hx:
    rol eax, 4
    mov edx, eax
    and edx, 15
    add dl, 48
    cmp dl, 57
    jbe h1
    add dl, 39
h1:
    mov [rdi], dl
    inc rdi
    loop hx
    call nl
    movzx ecx, byte ptr [r13+38]
    shl ecx, 8
    mov eax, 0x90001
    or eax, ecx
    mov [r15], eax
    lea eax, [r12+1]
    mov [r15+4], eax
    mov eax, [r13]
    mov [r15+8], eax
    mov dword ptr [r15+16], 19660950
    mov dword ptr [r15+20], 0x10000
    mov eax, [r13+32]
    mov [r15+24], eax
    mov dword ptr [r15+28], 0x800
    mov dword ptr [r15+32], 3
    push 36
    pop rdx
    call sendr
    mov dword ptr [r15], 0x20008
    push 8
    pop rdx
    call sendr
    mov edi, 300000000
    call slp
    mov dword ptr [r15], 0x50037
    lea eax, [r12+1]
    mov [r15+8], eax
    mov dword ptr [r15+12], 4
    xor r14d, r14d
gcl:
    lea eax, [r12+r14+2]
    mov [r15+4], eax
    mov eax, [r14*4+colors]
    mov [r15+16], eax
    push 20
    pop rdx
    call sendr
    inc r14d
    cmp r14d, 8
    jb gcl
    mov edi, ebx
    push 4
    pop rsi
    mov edx, 0x800
    push 72
    pop rax
    syscall
    call spawn
    xor r14d, r14d
frame:
    xor r13d, r13d
poll:
    mov edi, ebx
    mov esi, offset buf
    mov edx, 4096
    xor eax, eax
    syscall
    test eax, eax
    jle pd
    mov r8d, offset buf
    lea r9, [r8+rax]
evl:
    movzx eax, byte ptr [r8]
    and al, 0x7f
    movzx r10d, byte ptr [r8+1]
    mov esi, offset s_press
    cmp al, 2
    jne notp
    mov edi, offset keys
    push 4
    pop rcx
    mov al, r10b
    repne scasb
    jne pr
    push 4
    pop r13
    sub r13d, ecx
    jmp pr
notp:
    mov esi, offset s_rel
    cmp al, 3
    jne nxev
pr:
    call say
nxev:
    add r8, 32
    cmp r8, r9
    jb evl
    jmp poll
pd:
    cmp byte ptr [rbp+24], 0
    jne render
    mov edi, [rbp+8]
    mov esi, [rbp+12]
    mov edx, [rbp+16]
    dec r13d
    js grav
    jnz na
    dec esi
    jmp try
na:
    dec r13d
    jnz nb
    inc esi
    jmp try
nb:
    dec r13d
    jnz rt
    inc edx
    jmp try
rt:
    inc edi
    and edi, 3
try:
    call collide
    jc grav
    mov [rbp+8], edi
    mov [rbp+12], esi
    mov [rbp+16], edx
grav:
    inc dword ptr [rbp+20]
    cmp dword ptr [rbp+20], 6
    jb render
    and dword ptr [rbp+20], 0
    mov edi, [rbp+8]
    mov esi, [rbp+12]
    mov edx, [rbp+16]
    inc edx
    call collide
    jc lck
    mov [rbp+16], edx
    jmp render
lck:
    dec edx
    call getbits
    mov r10d, [rbp+4]
    inc r10d
    xor ecx, ecx
lk:
    bt eax, ecx
    jnc lkn
    call xy
    imul r9d, r9d, 10
    add r9d, r8d
    mov [rbp+r9+28], r10b
lkn:
    inc ecx
    cmp ecx, 16
    jb lk
    push 19
    pop r8
    push 19
    pop r9
lnl:
    imul edx, r9d, 10
    lea rsi, [rbp+rdx+28]
    mov rdi, rsi
    xor eax, eax
    push 10
    pop rcx
    repne scasb
    jne lsk
    imul edx, r8d, 10
    lea rdi, [rbp+rdx+28]
    push 10
    pop rcx
    rep movsb
    dec r8d
lsk:
    dec r9d
    jns lnl
    lea rdi, [rbp+28]
    lea ecx, [r8+1]
    imul ecx, ecx, 10
    xor eax, eax
    rep stosb
    call spawn
render:
    mov dword ptr [r15+12], 0
    mov dword ptr [r15+16], 19660950
    lea rdi, [r15+20]
    push 2
    pop rsi
    call poly
    push 1
    pop r13
cloop:
    xor eax, eax
    cmp byte ptr [rbp+24], al
    jne cgo
    mov ecx, [rbp+4]
    inc ecx
    cmp ecx, r13d
    jne cgo
    mov edi, [rbp+8]
    call getbits
cgo:
    lea rdi, [r15+12]
    xor r8d, r8d
rowl:
    xor r9d, r9d
coll:
    imul ecx, r8d, 10
    add ecx, r9d
    cmp [rbp+rcx+28], r13b
    je ad
    mov edx, r9d
    sub edx, [rbp+12]
    mov esi, r8d
    sub esi, [rbp+16]
    cmp edx, 4
    jae nx
    cmp esi, 4
    jae nx
    lea esi, [rdx+rsi*4]
    bt eax, esi
    jnc nx
ad:
    imul edx, r9d, 15
    imul esi, r8d, 15
    shl esi, 16
    or edx, esi
    mov [rdi], edx
    mov dword ptr [rdi+4], 0xf000f
    add rdi, 8
nx:
    inc r9d
    cmp r9d, 10
    jb coll
    inc r8d
    cmp r8d, 20
    jb rowl
    lea esi, [r13+2]
    call poly
    inc r13d
    cmp r13d, 8
    jb cloop
    mov esi, offset s_frame
    mov r10d, r14d
    call say
    mov edi, 40000000
    call slp
    inc r14d
    cmp r14d, 1500
    jb frame
    xor edi, edi
    jmp ex
fail:
    mov edi, 1
ex:
    mov eax, 231
    syscall

poly:
    mov rdx, rdi
    sub rdx, r15
    cmp edx, 12
    je pyr
    mov eax, edx
    shl eax, 14
    add eax, 70
    mov [r15], eax
    lea eax, [r12+1]
    mov [r15+4], eax
    or esi, r12d
    mov [r15+8], esi
pyr_go:
    jmp sendr
pyr:
    ret

spawn:
    imul eax, dword ptr [rbp], 1103515245
    add eax, 12345
    mov [rbp], eax
    shr eax, 16
    xor edx, edx
    push 7
    pop rcx
    div ecx
    mov [rbp+4], edx
    and dword ptr [rbp+8], 0
    mov dword ptr [rbp+12], 3
    and dword ptr [rbp+16], 0
    xor edi, edi
    mov esi, 3
    xor edx, edx
    call collide
    setc byte ptr [rbp+24]
    ret

getbits:
    mov eax, [rbp+4]
    lea eax, [rdi+rax*4]
    movzx eax, word ptr [rax*2+pieces]
    ret

xy:
    mov r8d, ecx
    and r8d, 3
    add r8d, esi
    mov r9d, ecx
    shr r9d, 2
    add r9d, edx
    ret

collide:
    call getbits
    xor ecx, ecx
cl1:
    bt eax, ecx
    jnc cl3
    call xy
    cmp r8d, 10
    jae cl2
    cmp r9d, 20
    jge cl2
    test r9d, r9d
    js cl3
    imul r9d, r9d, 10
    add r9d, r8d
    cmp byte ptr [rbp+r9+28], 0
    jne cl2
cl3:
    inc ecx
    cmp ecx, 16
    jb cl1
    ret
cl2:
    stc
    ret

slp:
    push rdi
    push 0
    mov rdi, rsp
    xor esi, esi
    push 35
    pop rax
    syscall
    pop rax
    pop rax
    ret

readn:
    xor eax, eax
    mov edi, ebx
    syscall
    test eax, eax
    jle fail
    add rsi, rax
    sub rdx, rax
    jg readn
    ret

cpy:
    mov edi, offset obuf
c1:
    lodsb
    stosb
    test al, al
    jnz c1
    dec rdi
    ret

say:
    call cpy
    mov eax, r10d
    push 10
    pop rcx
    call dc
nl:
    mov al, 10
    stosb
    mov esi, offset obuf
    mov rdx, rdi
    sub rdx, rsi
    push 1
    pop rdi
    jmp wr

dc:
    xor edx, edx
    div ecx
    push rdx
    test eax, eax
    jz d1
    call dc
d1:
    pop rax
    add al, 48
    stosb
    ret

sendr:
    mov rsi, r15
send:
    mov edi, ebx
wr:
    push 1
    pop rax
    syscall
    ret

keys:   .byte 38,40,39,25
colors: .long 0,0xFFFF,0xFFFF00,0x800080,0xFF00,0xFF0000,0xFF,0xFF8000
pieces: .word 240,17476,240,17476,102,102,102,102,114,562,624,1076,864,561,864,561,1584,306,1584,306,113,550,1136,802,116,1570,368,547
s_wid:   .asciz "window_id=0x"
s_press: .asciz "press "
s_rel:   .asciz "release "
s_frame: .asciz "frame="
sock:   .word 1
        .asciz "/tmp/.X11-unix/X0"
        .zero 90
setup:  .byte 0x6c,0
        .word 11,0,18,16,0
        .ascii "MIT-MAGIC-COOKIE-1"
        .byte 0,0
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

.bss
state: .zero 228
obuf:  .zero 32
req:   .zero 2048
buf:   .zero 16384
