#!/usr/bin/env bash
# Architecture parametrization for the asm / raw-bytes harnesses (sourced).
# ARCH=aarch64|x86_64 (env var; default: from `uname -m`).
# Sets: ARCH, ARCH_LABEL, ASM_RULES, RAW_RULES, and spec_path().

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) ARCH=aarch64 ;;
  amd64) ARCH=x86_64 ;;
esac

case "$ARCH" in
aarch64)
  ARCH_LABEL="AArch64"
  ASM_RULES="Target: Linux AArch64 (ARM64), GNU assembler (GAS) syntax.
Rules:
- Raw Linux syscalls only (svc #0, syscall number in x8, args in x0-x5, return in x0). NO libc, NO C library calls, NO crt startup.
- Must define '.global _start' as the entry point (not 'main').
- Must end by calling the exit_group syscall (number 94) directly — do not fall off the end.
- Relevant AArch64 Linux syscall numbers: read=63 write=64 exit=93 exit_group=94 socket=198 bind=200 listen=201 accept=202 close=57.
- socket/bind/accept struct layouts follow standard Linux sockaddr_in (AF_INET=2)."
  RAW_RULES="Target: Linux ELF64, AArch64 (ARM64) architecture, little-endian, statically linked, no dynamic loader.
You must emit the COMPLETE raw bytes of a working ELF64 executable: ELF header, one PT_LOAD program header, and the AArch64 machine code instructions (encoded by hand as raw 32-bit little-endian words — you know the AArch64 instruction encoding), using raw Linux syscalls (svc #0, syscall number in x8, args in x0-x5). No libc, no crt, no relocations, no sections needed — just a minimal valid ELF64 with e_entry pointing at your code within the single PT_LOAD segment.
Relevant AArch64 Linux syscall numbers: write=64 exit=93 exit_group=94.
Output format: ONLY a continuous stream of hex digit pairs representing every byte of the file in order, nothing else — no spaces required but allowed, no markdown fences, no explanation, no 0x prefixes."
  ;;
x86_64)
  ARCH_LABEL="x86-64"
  ASM_RULES="Target: Linux x86-64, GNU assembler (GAS) syntax. Use '.intel_syntax noprefix' at the top of the file.
Rules:
- Raw Linux syscalls only (the 'syscall' instruction, syscall number in rax, args in rdi rsi rdx r10 r8 r9, return in rax; rcx and r11 are clobbered). NO libc, NO C library calls, NO crt startup.
- Must define '.global _start' as the entry point (not 'main').
- Must end by calling the exit_group syscall (number 231) directly — do not fall off the end.
- Relevant x86-64 Linux syscall numbers: read=0 write=1 close=3 nanosleep=35 socket=41 connect=42 accept=43 bind=49 listen=50 setsockopt=54 fcntl=72 exit=60 exit_group=231.
- socket/bind/accept struct layouts follow standard Linux sockaddr_in (AF_INET=2)."
  RAW_RULES="Target: Linux ELF64, x86-64 architecture (e_machine=0x3E=62, EI_DATA=little-endian), statically linked, no dynamic loader.
You must emit the COMPLETE raw bytes of a working ELF64 executable: ELF header, one PT_LOAD program header, and the x86-64 machine code instructions (encoded by hand as variable-length instructions — you know the x86-64 instruction encoding), using raw Linux syscalls (the 'syscall' instruction 0F 05, syscall number in rax, args in rdi rsi rdx r10 r8 r9). No libc, no crt, no relocations, no sections needed — just a minimal valid ELF64 with e_entry pointing at your code within the single PT_LOAD segment.
Relevant x86-64 Linux syscall numbers: write=1 exit=60 exit_group=231.
Output format: ONLY a continuous stream of hex digit pairs representing every byte of the file in order, nothing else — no spaces required but allowed, no markdown fences, no explanation, no 0x prefixes."
  ;;
*)
  echo "Unsupported ARCH='$ARCH' (use aarch64 or x86_64)" >&2; return 1 2>/dev/null || exit 1 ;;
esac

# spec_path <example-dir>: spec.<arch>.md if present, else spec.md
spec_path() {
  if [ -f "$1/spec.$ARCH.md" ]; then echo "$1/spec.$ARCH.md"; else echo "$1/spec.md"; fi
}
