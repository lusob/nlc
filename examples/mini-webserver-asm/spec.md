A minimal single-threaded HTTP/1.1 server for Linux AArch64, using ONLY
raw Linux syscalls (no libc). Requirements:

- Create a TCP socket (AF_INET=2, SOCK_STREAM=1), syscall socket=198.
- Set SO_REUSEADDR (SOL_SOCKET=1, SO_REUSEADDR=2) via setsockopt,
  syscall setsockopt=208, so restarts don't fail with "Address already
  in use".
- Bind to 127.0.0.1:8124 (syscall bind=200) using a standard 16-byte
  sockaddr_in: sin_family=2 (2 bytes, little-endian in memory as raw
  struct field but the VALUE 2 fits in one byte so endianness doesn't
  matter here), sin_port=8124 in NETWORK byte order (big-endian: 0x1FB4
  wait compute properly: 8124 = 0x1FBC, so bytes on the wire are 0x1F,
  0xBC), sin_addr=127.0.0.1 = 0x7F000001 stored as raw bytes 127,0,0,1
  in address order (also effectively network byte order for this
  value), followed by 8 bytes of zero padding.
- Listen (syscall listen=201) with backlog 16.
- Print `Listening on port 8124\n` to stdout (write syscall) right after
  bind+listen succeed, before the accept loop.
- Loop: accept (syscall accept=202) a connection, read the request
  (read syscall, a few hundred bytes is enough, don't need to fully
  parse it), then write back exactly:
  `HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC`
  then close the connection (close syscall=57) and loop back to accept
  again — must NOT exit after one request, must keep serving.
