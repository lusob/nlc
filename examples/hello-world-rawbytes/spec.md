A program that writes exactly `Hello, world!\n` (14 bytes, with trailing
newline, no other bytes) to file descriptor 1 (stdout) using the write
syscall directly, then exits with status code 0 using the exit_group
syscall directly. No libc, no C runtime.
