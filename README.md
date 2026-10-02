# NLC

Loop-engineering experiment: instead of a human prompting an LLM turn by
turn, a Bash harness **is** the loop — it prompts Claude headlessly
(`claude -p`), builds the output, runs a hard verification gate, feeds real
errors back as the next prompt, and repeats until the smoke test passes or
the iteration budget is exhausted.

The twist: each program is generated at three progressively lower levels of
abstraction, testing how far down the stack a code model can go with no
human in the loop:

| Variant | Harness | LLM emits | Toolchain involved |
|---|---|---|---|
| A | `harness/run_loop.sh` | single-file C (C11/POSIX, libc only) | `gcc` |
| B | `harness/run_loop_asm.sh` | raw AArch64 GNU assembly, Linux syscalls only (`svc #0`), no libc, no crt | `as` + `ld` only |
| C | `harness/run_loop_rawbytes.sh` | the complete ELF64 AArch64 executable as raw hex bytes — hand-encoded ELF header, program header, and machine-code words | none: `xxd -r` + `chmod +x` |

## How it works

Each example directory contains everything the loop needs:

```
examples/<name>/
├── spec.md         # natural-language spec (the ONLY input the model gets)
├── smoke_test.sh   # verification gate: takes binary path as $1, exit 0 = pass
├── main.c|.s|.hex  # generated source (variant-dependent)
├── app             # built binary
└── run.log         # full transcript of the loop (iterations + feedback)
```

Usage:

```sh
harness/run_loop.sh          examples/hello-world           # C,      default 5 iters
harness/run_loop_asm.sh      examples/hello-world-asm       # asm,    default 6 iters
harness/run_loop_rawbytes.sh examples/hello-world-rawbytes  # bytes,  default 8 iters

# <example-dir> [max_iters] [model]   (default model: fable)
```

Per iteration:

1. Prompt the model with the spec (+ accumulated error feedback on retries).
2. Strip fences → write source (or hex-decode to binary for variant C).
3. Build and/or validate (`as`/`ld`, or `readelf -h` sanity check).
4. Run `smoke_test.sh`. Pass → done. Fail → its stdout/stderr becomes the
   next prompt's feedback.

## Examples & results

All runs below used model `fable` on native Linux AArch64. "Iters" is the
iteration that passed / budget.

| Example | Variant | Result | Binary size |
|---|---|---:|---:|
| `hello-world` | C | 1/5 | 71,624 B |
| `hello-world-asm` | asm | 1/6 | 1,072 B |
| `hello-world-rawbytes` | raw bytes | 5/8 | **166 B** |
| `mini-webserver` | C | 2/6 | 75,992 B |
| `mini-webserver-asm` | asm | 2/8 | 1,784 B |
| `mini-webserver-rawbytes` | raw bytes | 4/15 | 696 B |
| `counter-server-rawbytes` | raw bytes | interrupted at iter 5 (no verdict logged) | — |
| `plasma-demo-asm` | asm (terminal plasma) | 1/15 | 1,712 B |
| `cube3d-asm` | asm (rotating wireframe cube, terminal) | 1/25 | 3,536 B |
| `x11-m1-handshake-asm` … `x11-m6-fire-asm` | asm (X11 demoscene milestones) | all pass (1–4 iters) | 2.3–7 KB |
| `doom-d1-input-asm` / `-d2-raycast-` / `-d3-playable-` | asm (playable raycaster) | all pass (d3: 2 iters) | 3.0–6.2 KB |
| `tetris-t1-core-asm` | asm (playable Tetris on X11, explicit size-minimization exercise) | 2/25 | 6,752 B |

Highlights:

- **Raw-bytes tier works**: the model hand-encodes a valid ELF64 + machine
  code — e.g. a 166-byte static hello-world, and a stateful HTTP server
  (real counter arithmetic, correct Content-Length across digit growth) in
  under 2 KB of hand-built ELF.
- **X11 without libc**: the milestone series (`m1` handshake → `m2` window →
  `m3/m4` shaded cube → `m5` scroller → `m6` fire → final combined demo)
  talks to the X server over its Unix socket with raw syscalls, MIT-MAGIC-
  COOKIE auth, and hand-packed request structs.
- **Verification scales with difficulty**: simple examples verify output
  text; graphical/game examples pair `smoke_test.sh` with Python verifiers
  (`verify.py`) that parse frame dumps; servers are exercised with `curl`.
- Feedback loops matter most at the bottom tier: hello-world needed 5
  iterations of assembler-error-driven fixes before the raw ELF ran.

## Requirements

- Linux on AArch64 (targets are ARM64; no emulation layer assumed).
- Bash, `xxd`, `readelf`, `curl`, `python3` (for verifier scripts), GNU
  `binutils` (`as`, `ld`) and `gcc` for variants A/B.
- Claude CLI authenticated, with the `fable` model available.

## Portability / status

Everything here is **AArch64-only** today (specs, prompts and verifiers pin
AArch64 syscall numbers, `svc #0`, and ELF `e_machine`). x86-64 support is the
next step: parametrize the architecture in the three `harness/run_loop*.sh`
prompts (syscall ABI, instruction encoding, ELF machine type) and in each
example's `spec.md`, then validate on real Intel hardware.

X11 examples: `spec.md` contains `@@XAUTH_COOKIE@@` instead of a cookie; the
harness fills it at run time from `xauth list $DISPLAY` (`harness/xauth_cookie.sh`).
The committed `main.s` files have the cookie bytes zeroed, so they won't
authenticate as-is — re-run the loop on your own machine to regenerate them.

## Notes

- `tmp/` holds one-off generators used while authoring specs (tetromino
  bit-packing, 5x7 font, fire palette, sine tables) plus reference
  implementations — not part of the harness.
- Specs deliberately pin down every byte-level detail (struct layouts,
  endianness, syscall numbers, exact response strings) so the smoke test is
  unambiguous and failure feedback is actionable.
