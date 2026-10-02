A minimal single-threaded HTTP/1.1 server in C using only POSIX sockets
(no external libraries). Requirements:

- Listens on TCP port 8123 on 127.0.0.1.
- Sets SO_REUSEADDR on the listening socket so restarts don't fail with
  "Address already in use".
- On any HTTP GET request (to any path), responds with:
  `HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC`
- Handles one connection at a time in a simple accept loop (no threading,
  no forking needed).
- Runs indefinitely until killed (e.g. by SIGTERM) — it must NOT exit
  after serving one request.
- Prints `Listening on port 8123` to stdout (and flushes stdout) right
  after the socket is bound and listening, before entering the accept
  loop — this is used by the test harness to know when it's safe to send
  requests.
