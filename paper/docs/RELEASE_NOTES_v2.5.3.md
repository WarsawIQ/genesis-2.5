# GENESIS 2.5.3

A correctness release for the build and the script interpreter. No solver,
kernel or model behaviour changes; every number the manuscript reports still
stands.

Two defects are fixed, and they have the same shape: both were silent. One made
a fresh checkout stop with an error that pointed at the wrong file, and one let
a mistyped `include` corrupt the heap and then either crash the process or hang
it for as long as the queue allowed — never reporting a usable exit status. The
first was the leading Known issue of v2.5.2 and is now closed.

## A clean clone builds again

`genesis/src/diskio/interface/Makefile` builds its subdirectories through a
stamp rule:

```make
fflibs:
	@(for subdir in $(DISKIOSUBDIR); do cd $$subdir; make ...; cd ..; done)
	-touch fflibs
```

The rule is correct. What was wrong is that `genesis/src/diskio/interface/fflibs`
— the zero-length file the rule touches on completion — was tracked in the
repository. Every clone therefore started with the stamp already present, `make`
considered the target satisfied, and it **never descended** into `netcdf` or
`FMT1`. `FMT1lib.o` was never built, and the link step that needs it failed with
`No rule to make target 'diskio/interface/netcdf/netcdflib.o'` — a message that
names a different object than the one actually missing, which is why the cause
took a while to find.

A tree that had been built before never hit this, because its objects survived.
That is why it went unnoticed until v2.5.2 was packaged from a fresh checkout.

Measured on a clean tree materialised with `git archive`, zero `.o` files
present:

| tree | result |
|---|---|
| v2.5.2, documented README procedure | fails, no `FMT1lib.o`, no binary |
| the same plus `rm -f diskio/interface/fflibs` | builds, `FMT1lib.o` 34 456 B, binary 2 434 464 B |
| **this release** | builds, exit status 0, identical sizes |

The third row is the one that matters: it is not the second. The second removed
the stamp by hand; the third is the tree a reader gets after cloning.

The stamp is now untracked and ignored. **v2.5.3 is the first release that
builds from a clean clone**, so it ships a binary tarball again.

## A missing `include` no longer corrupts the heap

Both `include` rules in `genesis/src/ss/script.y` released their operands inside
the not-found branch and then fell through to code that used or released them
again:

```c
if (!IncludeScript(argc, argv))
  {
    sprintf(argbuf, "Script '%s' not found", $2);
    free($2);                      /* released here ... */
    yyerror(argbuf);
  }

if (Compiling || InFunctionDefinition)
  {
    v.r_str = $2;                  /* ... then stored in the parse tree */
  }
else
  {
    free($2);                      /* ... or released a second time */
  }
```

`yyerror` reports; it does not unwind. So a script naming a file that is not on
`SIMPATH` left either a dangling pointer inside the parse tree or a double free,
and from there the process was in undefined behaviour. The rule taking arguments
did the same to `$4` by way of `FreePTValues` and `PTFree`.

What a user saw depended on where the heap happened to be corrupted: a
segmentation fault, or a process left alive doing nothing. Measured on three
script shapes, all with `-nox` and stdin on `/dev/null`, and with a real
`.simrc` present:

| script | v2.5.2 | v2.5.3 |
|---|---|---|
| missing `include` alone | exit 139, segmentation fault | no crash |
| missing `include` after a successful one | no crash | no crash |
| missing `include` followed only by `quit` | no crash | no crash |

The error message is printed in every case, before and after.

The fix is to report and continue: the not-found branch no longer frees
anything, and the existing code below releases each operand exactly once, or
hands it to the parse tree, as it already did on the success path.

**What this fixes is the memory corruption, and only that.** The crash is gone
and the parser's state is sound afterwards. What it does *not* change is that
the interpreter still drops to its interactive prompt on a script error and
stays there — see Known issues. A batch caller therefore still needs its own
timeout, and still cannot rely on the exit status; what it gains is that the
process is no longer in undefined behaviour while it waits.

Whether an individual case crashed or hung was never stable: it depended on the
allocator's state, which is what heap corruption means. That is why the same
script shape was seen to segfault under one build and hang under another.

## Also in this release

- The version strings and the Makefile's `VERSION` move to 2.5.3.

## Known, not fixed here

- On very new toolchains (GCC 15.2 / glibc 2.42) the build completes but the
  binary segfaults during start-up inside `tset()`. GCC 8.5 builds a working
  binary. Not diagnosed.
- PGENESIS parallel initialisation does not come up on the UMCS cluster:
  `0 nodes requested`, every parallel-object fieldlist missing, segfault in
  0.3 s. Recorded since 2026-07-04; still open.
- **A script error still does not end the process.** The interpreter drops to
  its interactive prompt and blocks there, even with `-nox` and stdin on
  `/dev/null`, so a missing `include` still costs a batch job its whole time
  limit unless the caller imposes a timeout of its own. This is measured, not
  assumed: after the fix all three script shapes above still had to be killed.
  What v2.5.3 removes is the heap corruption underneath, not this. Making
  `-nox` with a non-tty stdin exit on the first script error is a behaviour
  change and belongs in a release that can carry one.
