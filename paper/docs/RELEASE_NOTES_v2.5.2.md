# GENESIS 2.5.2

A build-and-packaging release. No solver, kernel or model behaviour changes;
every number the manuscript reports still stands.

What changes is that a binary built from this tree no longer refuses to start
for want of a GPU runtime it never needed, and reports its own version rather
than 2.4. What has *not* changed, and is documented under Known issues below,
is that a clean checkout still does not build to completion — that is why this
release ships source only.

## The documented CPU build produced a binary that would not start

`-lOpenCL` had been appended to `TERMCAP`, the terminal-library variable, and
`TERMCAP` feeds `EXTRALIBS` — so every build linked it, including the plain
CPU/MPI build the README documents as "same as GENESIS 2.4". The accelerator
libraries are linked hard rather than `dlopen`'d, so such a binary does not fall
back to the CPU when `libOpenCL` is absent: it refuses to start, with a loader
error and no other output.

This is why a binary named `nxgenesis_nocl` — the CPU reference build — died on
cluster compute nodes while running fine on the login node, which happens to
have the driver libraries. `-lOpenCL` now arrives through a `GPULIBS` variable
set only under `USE_OPENCL`, and `-lcudart` likewise under `USE_CUDA`.

## The binary now reports its own version

`VERSIONSTR` and `VERSIONDATESTR` had not been touched since the 2.4 May 2019
update, so binaries built from `v2.5` and `v2.5.1` printed
`Release Version: 2.4 / Release Date: May 2019` while the release, the tag and
the SoftwareX metadata table all said otherwise. The Makefile's separate
`VERSION`, which names the install directory and the tarball, was 2.4 for the
same reason. **v2.5.2 is the first release whose binary agrees with its tag.**

## Also in this release

- `make srcdist` works again. It exported from SourceForge CVS, gone for years,
  so anyone following the upstream convention of building separate `genesis` and
  `pgenesis` source tarballs hit a dead protocol. It now takes the tree from the
  git checkout; the obsolete `.tar.Z` outputs are dropped, `.gz` and `.bz2` stay.
- The build traps are written down where people build, not only in a comment
  inside `cluster_bringup/10_build.sh`: `flex` shipped without `libfl` (with the
  stub recipe), `make clean` deleting generated sources that are only partly
  tracked, and `EXTRALIBS` replacing rather than appending. They are in
  `README.md` and in the four documents that travel inside the tarballs.
- The README is reordered around a first-time reader: what it is, a TL;DR
  against 2.4, then install. The v2.5 wrong-results defect keeps a warning above
  the fold and moves into a Known issues section.
- `pgenesis/README.txt`, `genesis/README`, `genesis/README.txt` and
  `genesis/README.bindist` carry a short note saying which version the reader is
  holding. Their original text is untouched.

## Known, not fixed here

- **A clean clone does not build.** Both `genesis` and `nxgenesis` stop with
  `No rule to make target 'diskio/interface/netcdf/netcdflib.o'`: the top-level
  `libs` step enters `diskio/` but never descends into
  `diskio/interface/netcdf/`. Building that object by hand works —
  `(cd diskio/interface/netcdf && make netcdflib.o)` — and the build still fails
  afterwards, on a cause not yet identified. A tree that has been built before
  does not hit this, because the objects survive, which is why it went unnoticed
  until this release was packaged from a fresh checkout. **This is why v2.5.2
  ships without a binary tarball**; one was built and verified earlier from a
  tree with prior build state, so the packaging procedure itself works.

- On very new toolchains (GCC 15.2 / glibc 2.42) the build completes but the
  binary segfaults during start-up inside `tset()`. GCC 8.5 builds a working
  binary. Not diagnosed.
- PGENESIS parallel initialisation does not come up on the UMCS cluster:
  `0 nodes requested`, every parallel-object fieldlist missing, segfault in
  0.3 s. Recorded since 2026-07-04; still open.
