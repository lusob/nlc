A minimal single-threaded HTTP/1.1 server for Linux ELF64 x86-64, as a
statically-linked executable with NO libc, NO crt, using ONLY raw Linux
syscalls encoded directly as x86-64 machine code (variable-length
instructions) inside a minimal hand-built ELF64 file. Requirements:

- Create a TCP socket (AF_INET=2, SOCK_STREAM=1), syscall socket=41.
- Set SO_REUSEADDR (SOL_SOCKET=1, SO_REUSEADDR=2) via setsockopt,
  syscall setsockopt=54, so restarts don't fail with "Address already
  in use".
- Bind to 127.0.0.1:8125 (syscall bind=49) using a standard 16-byte
  sockaddr_in: sin_family=2, sin_port=8125 in NETWORK byte order
  (8125 = 0x1FBD, so the two port bytes on the wire are 0x1F, 0xBD),
  sin_addr=127.0.0.1 stored as raw bytes 127,0,0,1, followed by 8 bytes
  of zero padding.
- Listen (syscall listen=50) with backlog 16.
- Print `Listening on port 8125\n` to stdout (write syscall=1) right
  after bind+listen succeed, before the accept loop.
- Loop: accept (syscall accept=43) a connection, read the request
  (read syscall=0, a few hundred bytes buffer is enough, no need to
  parse it), then write back exactly:
  `HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC`
  then close the connection (close syscall=3) and loop back to accept
  again — must NOT exit after one request, must keep serving forever.

You must emit the COMPLETE raw bytes of a working ELF64 executable by
hand: ELF header, one PT_LOAD program header covering the whole file
(code + data + bss-equivalent, since there's no loader to zero-fill
bss — just reserve static space within the loaded segment and it will
contain whatever is on disk, so initialize any scratch buffer bytes to
zero explicitly in the file if you need zeroed memory, or just don't
rely on it being zeroed), and the x86-64 machine code instructions
encoded as raw variable-length words. e_entry must point at your
_start code within the single PT_LOAD segment. No relocations, no
dynamic linking, no section headers needed.
