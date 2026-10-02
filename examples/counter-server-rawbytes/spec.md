A minimal single-threaded HTTP/1.1 server for Linux ELF64 AArch64, as a
statically-linked executable with NO libc, NO crt, using ONLY raw Linux
syscalls encoded directly as AArch64 machine code (32-bit little-endian
instruction words) inside a minimal hand-built ELF64 file (no
assembler, no linker — you emit the final file bytes directly).

This is harder than a fixed-response server: it must maintain state and
do real arithmetic, not just echo fixed bytes.

Requirements:

- Create a TCP socket (AF_INET=2, SOCK_STREAM=1), syscall socket=198.
- Set SO_REUSEADDR (SOL_SOCKET=1, SO_REUSEADDR=2) via setsockopt,
  syscall setsockopt=208.
- Bind to 127.0.0.1:8126 (syscall bind=200): sockaddr_in with
  sin_family=2, sin_port=8126 in network byte order (8126 = 0x1FBE, so
  wire bytes are 0x1F, 0xBE), sin_addr=127.0.0.1 as raw bytes
  127,0,0,1, then 8 zero padding bytes.
- Listen (syscall listen=201), backlog 16.
- Print `Listening on port 8126\n` to stdout (write syscall=64) right
  after bind+listen succeed, before the accept loop.
- Keep an integer counter starting at 0, stored in writable memory
  within your loaded segment (do not assume the loader zero-fills
  anything not present in the file — if you need it to start at zero,
  make sure the byte(s) on disk at that location are actually zero).
- Loop forever: accept (syscall accept=202) a connection, read the
  request (read syscall=63, a small buffer is enough, you don't need
  to parse it), INCREMENT the counter by 1, then convert the new
  counter value to a decimal ASCII string (no leading zeros, e.g. 1,
  2, ... 10, 11...) using real arithmetic (repeated division by 10 and
  building the digit string, most significant digit first — this must
  work correctly for at least values 1 through 20, i.e. it must
  correctly transition from single-digit to two-digit numbers), then
  write back an HTTP response of exactly this shape, with a REAL,
  correctly computed Content-Length matching the exact byte length of
  the body that follows (the body length changes as the number grows
  more digits):

  HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: <N>\r\n\r\nRequest count: <counter>

  (where `<counter>` is the decimal digits with no trailing newline,
  and `<N>` is the exact length in bytes of "Request count: <counter>")

  Then close the connection (close syscall=57) and go back to accept
  — must never exit, must keep serving indefinitely, and the counter
  must genuinely persist and increment across requests (request 1 gets
  count 1, request 2 gets count 2, etc — verified by making several
  requests in a row and checking the numbers are sequential, not
  stuck at the same value).
