MILESTONE 1 of an X11 demoscene demo, for Linux AArch64, raw syscalls
only (no libc), GAS assembly, entry point `_start`, assembled with
`as`, linked with `ld` — no compiler. This milestone: connect to the
X11 server, authenticate, complete the connection handshake, and print
the root window ID and root visual ID. No window is created yet — that
is a later milestone.

Syscall numbers: socket=198, connect=203, read=63, write=64, exit_group=94.

## Connect

Create a AF_UNIX (domain=1) SOCK_STREAM (type=1) socket (protocol=0):
`socket(1, 1, 0)`.

Connect to the Unix domain socket at path `/tmp/.X11-unix/X0` using a
`sockaddr_un`: 2 bytes `sa_family` = 1 (AF_UNIX, little-endian
halfword), followed by the path bytes `/tmp/.X11-unix/X0` (18 ASCII
bytes) then a NUL byte, then zero-pad the rest of a 108-byte
`sun_path` field. Total struct = 110 bytes (2 + 108). Pass addrlen=110
to `connect`.

## Send the connection setup request

The X11 "ClientPrefix" request, exact byte layout (12-byte fixed
header, then name, then data, name and data each padded to a multiple
of 4 bytes with zero bytes):

```
offset 0:  byte 'l' (0x6c)         — byte order: little-endian
offset 1:  byte 0                  — unused
offset 2:  u16 LE = 11             — protocol-major-version
offset 4:  u16 LE = 0              — protocol-minor-version
offset 6:  u16 LE = 18             — length of auth-protocol-name ("MIT-MAGIC-COOKIE-1" is 18 bytes)
offset 8:  u16 LE = 16             — length of auth-protocol-data (16-byte cookie)
offset 10: u16 LE = 0              — unused (IMPORTANT: this field exists, don't skip it)
offset 12: "MIT-MAGIC-COOKIE-1"    — 18 bytes, then 2 bytes of zero padding (18 is not a multiple of 4, pad to 20)
offset 32: the 16-byte cookie (hex, use these EXACT bytes):
           @@XAUTH_COOKIE@@
           (16 is already a multiple of 4, no padding needed)
```
Total request = 48 bytes. Write all 48 bytes to the socket in one `write` call (or a small loop if a single write doesn't send everything — check the return value).

## Read the reply

Read exactly 8 bytes first (the reply header):
```
offset 0: u8  success       (1 = Success — this MUST be 1; if it's 0, something is wrong with the auth, print "AUTH FAILED" and exit 1)
offset 1: u8  reserved
offset 2: u16 LE major version
offset 4: u16 LE minor version
offset 6: u16 LE addl_len   — length of the data that follows, in UNITS OF 4 BYTES (so the actual byte count is addl_len*4)
```
Then read exactly `addl_len*4` more bytes (this can be a few thousand bytes — allocate a buffer of at least 16384 bytes and loop on `read` until you've received all of it, since a single `read` syscall on a socket is not guaranteed to return everything at once).

Keep the 8-byte header AND the additional data in ONE contiguous buffer in memory (i.e. read the header into buffer[0..8), then the additional data into buffer[8..8+addl_len*4)) so the absolute offsets below all measure from the start of that one buffer.

## Parse out the root window ID and root visual ID

Using ABSOLUTE offsets into that one combined buffer (header + data):

```
offset 24: u16 LE  vendor_len (v)         — length of the vendor string
offset 29: u8      num_formats            — number of pixmap-format structures that follow the vendor string
```

Compute:
```
vendor_end  = 40 + ((vendor_len + 3) & ~3)      // 40 = 8 (header) + 32 (fixed setup fields), then vendor string padded up to a multiple of 4
root_offset = vendor_end + num_formats * 8       // each pixmap-format structure is 8 bytes
```

Then:
```
root_window_id = 4 bytes LE at buffer[root_offset .. root_offset+4)
root_visual_id = 4 bytes LE at buffer[root_offset+32 .. root_offset+36)
```

## Output

Print to stdout (write syscall, fd=1) two lines of TEXT (convert the
32-bit values to 8-digit lowercase hex ASCII yourself, most
significant nibble first — no printf, no libc, do the nibble-to-hex-char
conversion by hand):
```
root_window=0xXXXXXXXX
root_visual=0xXXXXXXXX
```
(exactly those two lines, each ending with \n, "0x" prefix, exactly 8
lowercase hex digits, zero-padded)

Then exit_group(0). If the auth failed (success byte was 0), instead
print `AUTH FAILED\n` to stdout and exit_group(1).
