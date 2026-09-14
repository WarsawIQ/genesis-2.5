# GENESIS 2.5.4

A correctness release for start-up. No solver, kernel or model behaviour
changes; every number the manuscript reports still stands.

One defect is fixed, and it closes the leading Known issue of v2.5.3. That
issue was recorded as a toolchain problem — "on very new toolchains the build
completes but the binary segfaults during start-up inside `tset()`" — with the
advice to prefer an older compiler. **The attribution was wrong and the advice
did not help.** The compiler had nothing to do with it.

## An uninitialised character count smashed the stack at start-up

`AvailableCharacters()` in `src/shell/shell_io.c` declared

```c
int nc;
```

and then called

```c
ioctl(fileno(stdin), FIONREAD, &nc);
```

without looking at the result. `ioctl()` fails on anything that is not a
character device — `/dev/null`, a closed descriptor, a pipe on some systems —
and on failure it leaves `nc` untouched. The function therefore returned an
uninitialised stack slot, and every caller used it as a count of characters
waiting to be read.

`tset()` is the caller that turns that into a crash:

```c
char buffer[1000];
nc = AvailableCharacters();
if (nc) {
    for (i = 0; i < nc; i++)
        buffer[i] = getc(stdin);
}
```

Any large garbage value walks off the end of the frame.

Redirecting a batch run from `/dev/null` is enough to trigger it, which is what
every job script does. Whether it triggers at all depends on what happens to be
in that stack slot, which the environment block decides — so the same source
crashed on one machine and ran on the next, and one unpatched binary crashed
under `TERM=linux` and `TERM=dumb` while running cleanly under `TERM=xterm` and
`TERM=vt100`. Note that `linux` and `xterm` are the same length: it is the
contents of the environment that move the stack, not any property of the
terminal. That is what made it look like a compiler or libc problem, and it was
carried as a toolchain Known issue in both v2.5.2 and v2.5.3.

The fix initialises `nc`, checks the `ioctl` return, clamps a negative result to
zero, and bounds the copy in `tset()` against the size of its own buffer — the
source is corrected, and the one call site that writes into a fixed buffer no
longer trusts the count it is handed.

### Measured

| | start-ups completed |
|---|---|
| v2.5.3, `TERM=linux`, stdin from `/dev/null` | **0 / 20** |
| v2.5.4, same conditions | 20 / 20 |

Linux 7.0.0, GCC 15.2.0, glibc 2.42, x86-64.

### Reproduced on a second architecture

The same three-point probe of membrane time constant was run on x86-64
(GCC 15.2, glibc 2.42) and on aarch64 (Raspberry Pi 4B, Ubuntu 22.04.5,
GCC 11.4, glibc 2.35), each with a binary built from these sources on the
machine that ran it. Start-up: 20/20 on both. The measured values agree to
every digit printed — membrane time constants of 16.05, 38.90 and 19.05 ms,
resting potentials of −78.84, −79.75 and −74.12 mV, with input resistance and
spike counts likewise identical.

## Also in this release

- The version strings and the Makefile's `VERSION` move to 2.5.4.
- The README's build-troubleshooting section no longer advises choosing an
  older compiler to avoid the start-up crash. That advice was based on the
  wrong diagnosis.

## Known, not fixed here

- PGENESIS parallel initialisation does not come up on the UMCS cluster:
  `0 nodes requested`, every parallel-object fieldlist missing, segfault in
  0.3 s. Recorded since 2026-07-04; still open.
- **A script error still does not end the process.** The interpreter drops to
  its interactive prompt and blocks there, even with `-nox` and stdin on
  `/dev/null`, so a missing `include` still costs a batch job its whole time
  limit unless the caller imposes a timeout of its own. Unchanged from v2.5.3,
  and confirmed again here: with the start-up crash gone, a missing `include`
  prints its error and then hangs until killed. Making `-nox` with a non-tty
  stdin exit on the first script error is a behaviour change and belongs in a
  release that can carry one.
