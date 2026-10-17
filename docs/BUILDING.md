# Building GENESIS 2.5

The short version is in the [README](../README.md#install). This page has the
details and the failures that account for nearly every build problem reported
on this tree.

## Requirements

Linux x86_64, GCC, GNU make, flex, bison and ncurses. Beyond that:

- OpenCL backend: an OpenCL 1.2+ runtime (tested with the NVIDIA driver, ROCm
  6.3.1 and Mesa rusticl 26.1)
- CUDA backend: CUDA 12.x (tested with 12.8 on `sm_80`/A100, `sm_86`/A40 and
  `sm_89`/RTX 4090)
- PGENESIS: an MPI implementation (MPICH/Hydra or Open MPI)

Neither GPU backend is required.

**The accelerator builds link their runtime at start-up.** A binary built with
`USE_OPENCL=1` needs `libOpenCL.so.1` and one built with `USE_CUDA=1` needs
`libcudart.so.<major>`. Without them the binary does not fall back to the CPU;
it does not start at all:

```
nxgenesis: error while loading shared libraries: libOpenCL.so.1:
cannot open shared object file: No such file or directory
```

On a cluster this shows up in a particular way: the login node usually has the
driver libraries and the compute nodes often do not, so the same binary runs
interactively and fails the moment it is submitted. Point `LD_LIBRARY_PATH` at a
location the nodes can see (for example `LD_LIBRARY_PATH=/opt/cuda/lib64`), or
build the plain CPU target for the queue.

## Building

Plain CPU and MPI, as GENESIS 2.4:

```sh
cd genesis/src
make clean; make; make install
```

OpenCL:

```sh
cd genesis/src
make USE_OPENCL=1 nxgenesis
```

This builds `hsolve`'s OpenCL kernels (`genesis/src/hines/opencl/`) into
`nxgenesis` and links `-lOpenCL`. A run that reaches the GPU prints a start-up
line naming the backend and the precision, and a non-empty
`OCL PROFILING SUMMARY` at exit.

CUDA:

```sh
cd genesis/src
make USE_CUDA=1 CUDA_HOME=/usr/local/cuda nxgenesis
```

The CUDA kernels are a line-for-line port of the OpenCL ones behind the same
entry point, in fp32 by default and in fp64 with `GENESIS_GPU_PRECISION=fp64`
(one binary). If both `USE_OPENCL` and `USE_CUDA` are defined, CUDA wins. The
linker step is the part that goes wrong: see `EXTRALIBS` below and
[`genesis/src/hines/cuda/BUILD_CUDA.md`](../genesis/src/hines/cuda/BUILD_CUDA.md),
or use [`cluster_bringup/10_build.sh`](../cluster_bringup/10_build.sh), which
also picks the right `-arch` for the GPU it finds.
[`cluster_bringup/12_build_cpu.sh`](../cluster_bringup/12_build_cpu.sh) builds
the CPU-only binary with no GPU toolkit at all.

PGENESIS (MPI), after building GENESIS:

```sh
cd pgenesis/src
make install
```

**Check that `pgenesis/bin/pgenesis` is not empty.** The stock install rule
produces a 0-byte wrapper on this tree, and an empty wrapper silently removes
the `-nodes N` launch interface the PGENESIS documentation assumes. Regenerate
it with

```sh
sh pgenesis/regen_pgenesis_wrapper.sh
```

which makes the substitution the Makefile intends but leaves the path
placeholders in, so the wrapper finds its own location instead of baking in the
machine it was generated on. The wrapper is `#!/bin/csh -f`, so the host that
runs it needs csh or tcsh. Without either, launch the binary directly:
`mpirun -np <ranks> pgenesis/bin/Linux/nxpgenesis <script>.g` (the bare binary
does not accept `-nodes`).

## If the build fails

**`cannot find -lfl` or `undefined reference to yywrap`.** Many distributions
and most cluster images ship `flex` without `libfl`. GENESIS links its code
generator `code_g` with `-lfl`, so the build stops before it can generate the
`*_g@.c` sources everything else needs. `libfl` supplies one function here;
build a stub and point `LEXLIB` at it:

```sh
mkdir -p locallib
printf 'int yywrap(void){return 1;}\n' > locallib/yywrap.c
gcc -c locallib/yywrap.c -o locallib/yywrap.o
ar rcs locallib/libfl.a locallib/yywrap.o
make LEXLIB="$PWD/locallib/libfl.a" nxgenesis
```

Pass the same `LEXLIB=` to every later `make`, including `bindist`. The link
expects a `.a`; a bare `.o` does not work here.

**`No rule to make target 'diskio/interface/netcdf/netcdflib.o'`** on a fresh
clone of v2.5.2 or earlier: a committed stamp file made `make` skip the netcdf
subdirectory. Fixed in v2.5.3 (`aa163c5`); on an older tree,
`rm genesis/src/diskio/interface/fflibs` before building.

**`make clean` can make a working tree fail.** Some generated `*_g@.c` files are
tracked and some are not, so an incremental build can succeed where a clean one
fails: `clean` deletes the generated sources, and regenerating them needs
`code_g`, which needs the `libfl` fix above.

**`EXTRALIBS=` replaces the default; it does not add to it.** The default is
`$(SPRNGLIB) $(TERMCAP) $(GPULIBS)`. Passing `EXTRALIBS=-lcudart` silently drops
sprng and the terminal libraries. Pass the full set, as `10_build.sh` does.

**"no kernel image is available for execution on the device".** `make clean`
does not touch `hines/cuda/`, so an object built for another GPU architecture
links and then fails at run time. Remove `hines/cuda/*.o hines/hineslib.o` by
hand when switching cards.

**A segfault inside `tset()` at start-up** on v2.5.3 and earlier, depending on
the machine: `AvailableCharacters()` returned an uninitialised stack value
whenever `ioctl(FIONREAD)` failed, which it does on any stdin that is not a
character device. Fixed in v2.5.4; the toolchain was never the cause.
