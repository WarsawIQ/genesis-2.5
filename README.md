# GENESIS 2.5

**Latest release: [v2.5.4](https://github.com/WarsawIQ/genesis-2.5/releases/tag/v2.5.4)** ·
[archived on Zenodo](https://doi.org/10.5281/zenodo.22032886) ·
[draft manuscript](paper/manuscript_softwarex_submission.pdf)

GENESIS 2.5 is GENESIS 2.4 / PGENESIS 2.4 with two optional accelerator backends
for the `hsolve` compartmental solver — OpenCL and CUDA, behind the same
interface — plus fixes to the CPU solver that benefit everyone. **Your models,
scripts and MPI workflows do not change.** With no GPU backend enabled, GENESIS
behaves exactly as 2.4 did.

> ⚠️ **Running the `v2.5` tag or its Zenodo archive?** One class of model
> produces **wrong results** on the GPU there. Read
> [Known issues](#known-issues) before you trust any output. Fixed on `master`
> and in `v2.5.1`.

## Reproducing the paper

Every number in the paper and in this README is computed from raw data in this
repository. [`reproduce/claims.csv`](reproduce/claims.csv) names, for each one,
the data file, the rows and the formula; `python3 reproduce/make_numbers.py`
recomputes them all into the manuscript and into this file. To measure them
again on your own hardware:

```sh
sh reproduce/run_all.sh --cpu-only --quick   # ~2 min on a laptop, no GPU: solver fixes, construction, VAnet2 on one core
sh reproduce/run_all.sh --quick              # ~15 min, adds the accelerator claims (NVIDIA GPU, CUDA 12.x)
sh reproduce/run_all.sh                      # ~95 min, adds the sweeps and the spiking network
```

Or without installing anything, in a container ([`Dockerfile`](Dockerfile)):

```sh
docker build -t genesis25-cpu . && docker run --rm genesis25-cpu
```

Each run prints every published value beside yours with a verdict. The CPU-only
path and the container both run on every push, in
[GitHub Actions](.github/workflows/cpu-only.yml).
What reproduces which numbers, and what it needs:

<!-- claims-table:begin -->
| Numbers | Where they appear | Script that measures them | Needs | Time |
|---:|---|---|---|---|
| 1 | results text | `cluster_bringup/20_validate.sh` | any NVIDIA GPU, CUDA 12 | 5 min |
| 52 | dendritic-tree speedups (figure); dendritic-tree speedups (table) | `cluster_bringup/51_weekend_campaign.sh` | NVIDIA A100, NVIDIA A40 | 240 min |
| 12 | single-compartment speedups (table) | `cluster_bringup/53_singlecomp_walltime.sh` | NVIDIA A100, NVIDIA A40 | 30 min |
| 24 | results text; speedup against run length (table) | `cluster_bringup/55_multicomp_ksweep.sh` | NVIDIA A40 | 60 min |
| 6 | single-compartment speedups (table) | `cluster_bringup/56_opencl_cluster_bench.sh` | NVIDIA A100, NVIDIA A40 | 20 min |
| 26 | tab:sim | `cluster_bringup/campaign/E1_cross_simulator.sh` | NVIDIA A100, NVIDIA GPU with Arbor built for CUDA, NVIDIA GPU with the NVHPC CoreNEURON build | 65 min |
| 6 | abstract; fig:runlength; results text | `cluster_bringup/campaign/E2_ksweep.sh` | NVIDIA A100, NVIDIA A40 | 60 min |
| 26 | tab:regimes; tab:single | `cluster_bringup/campaign/E3_tables.sh` | NVIDIA A100, NVIDIA A40 | 60 min |
| 3 | fig:construction; sec:4 | `cluster_bringup/campaign/E3c_cpu.sh` | any Linux machine | 45 min |
| 4 | GPU crossover with Arbor (figure); results text | `cluster_bringup/campaign/E4_fp64_cost.sh` | NVIDIA A100, NVIDIA A40 | 25 min |
| 18 | results text | `cluster_bringup/campaign/E5_long_run.sh` | NVIDIA A100 | 35 min |
| 3 | sec:2 | `cluster_bringup/campaign/E7_imbalance.sh` | NVIDIA A100 | 30 min |
| 10 | sec:2 | `cluster_bringup/campaign/E8_graphs.sh` | NVIDIA A100, NVIDIA A40 | 20 min |
| 1 | fig:construction; sec:4 | `cluster_bringup/campaign/construction_before.sh` | any Linux machine | 30 min |
| 5 | sec:2 | `cluster_bringup/campaign/host_kernel_profile.sh` | NVIDIA A100 | 10 min |
| 52 | dendritic-tree speedups (figure); dendritic-tree speedups (table) | `cluster_bringup/clean_multicomp_sweep.sh` | NVIDIA A100, NVIDIA A40 | 240 min |
| 8 | dendritic trees against NEURON and Arbor (table) | `cluster_bringup/coreneuron/bench_multicomp_cross.sh` | NVIDIA GPU with Arbor built for CUDA, any Linux machine | 15 min |
| 1 | spiking network against NEURON and CoreNEURON (table) | `cluster_bringup/coreneuron/coreneuron_gpu_standalone.sh` | NVIDIA GPU with the NVHPC CoreNEURON build | 10 min |
| 26 | GPU crossover with Arbor (figure); abstract; dendritic trees against NEURON and Arbor (table); results text | `cluster_bringup/coreneuron/crossover_sweep.sh` | NVIDIA GPU with Arbor built for CUDA | 30 min |
| 3 | spiking network against NEURON and CoreNEURON (table) | `cluster_bringup/coreneuron/genesis_same_node.sh` | NVIDIA A100 | 10 min |
| 2 | results text | `cluster_bringup/coreneuron/rate_vs_walltime.sh` | NVIDIA GPU with Arbor built for CUDA | 20 min |
| 2 | spiking network against NEURON and CoreNEURON (table) | `cluster_bringup/coreneuron/spike_compare.sh` | NVIDIA A100 | 30 min |
| 2 | speedup against run length (table) | `cluster_bringup/verify_k5000.sh` | NVIDIA A40 | 30 min |
| 6 | model construction (figure); results text | `paper/scripts/plot_construction_scaling.py` | any Linux machine | 30 min |
| 4 | results text | `paper/scripts/run_pgenesis_mpi_scaling.sh` | MPI cluster, up to 24 ranks | 60 min |
| 1 | results text | `reproduce/stages/05_cpu.sh` | any Linux machine | 1 min |
| 29 | impact text; membrane-potential equivalence (figure); results text; spiking network against NEURON and CoreNEURON (table) | none yet: typed into the paper with no raw data kept; re-measured by the revision campaign | - | - |
<!-- claims-table:end -->

The comparison simulators (NEURON, CoreNEURON for the GPU, Arbor) are built from
recipes in [`cluster_bringup/toolchains/`](cluster_bringup/toolchains/), with
every path in [`cluster_bringup/env.sh`](cluster_bringup/env.sh).
[`reproduce/README.md`](reproduce/README.md) lists the four things that move
timings enough to matter.

## TL;DR — what 2.5 gives you over 2.4

| | |
|---|---|
| **GPU acceleration, opt-in** | OpenCL and CUDA backends for `hsolve` at `chanmode=4`/`5`. No model changes; leave them off and nothing differs from 2.4 |
| **Dendritic trees on the GPU** | `hines_tree_eliminate` runs the real Hines elimination, one thread per neuron — <!--claim:multicomp_step_a40_n50000-->37.3<!--/claim-->× (A40) / <!--claim:multicomp_step_a100_n50000-->80.8<!--/claim-->× (A100) step-phase at 50,000 × 16 compartments |
| **Isopotential networks on the GPU** | batched multi-step kernel, <!--claim:singlecomp_cuda_a40_n50000-->21.0<!--/claim-->× / <!--claim:singlecomp_cuda_a100_n50000-->21.9<!--/claim-->× end-to-end at N = 50,000, matching the fp64 CPU reference to ~1e-7 V |
| **Two Hines-solver defects fixed** | with several cells under one `hsolve`, GENESIS 2.4 numbered only the first cell's tree (wrong voltages in the others, backward Euler) and read outside its arrays at every other cell's root (Crank–Nicolson diverged and crashed) — CPU bugs, shown on unmodified 2.4 by `genesis/Scripts/tests/` on the `upstream-cpu-fixes` branch |
| **Model construction no longer quadratic** | four `O(n²)` scans removed; a 1.7-million-compartment model that never finished building now builds in <!--claim:construction_1700k_s-->51.5<!--/claim--> ± <!--claim:construction_1700k_s_sd-->0.6<!--/claim--> s. This holds for cells built element by element with `create`; copying a whole prototype cell N times under one parent is still quadratic (each `copy` checks its new name against every sibling) |
| **Faster than NEURON on one CPU core** | Vogels–Abbott COBAHH, 4000 cells, 5 s, one solver per layer: <!--claim:vanet2_vs_coreneuron_cpu-->2.30<!--/claim-->× vs CoreNEURON, <!--claim:vanet2_vs_neuron_cpu-->2.89<!--/claim-->× vs NEURON 9.0.2 |

Both the solver fix and the construction fix apply whether or not you ever touch
a GPU.

## Install

Nothing here needs root or a scheduler. Linux, x86_64, GCC, GNU Make.

**CPU only — the safe default, and all you need to run existing models:**

```sh
git clone https://github.com/WarsawIQ/genesis-2.5.git
cd genesis-2.5/genesis/src
make clean && make && make install
```

**With a GPU** — pick one backend; if both are defined CUDA wins:

```sh
make USE_CUDA=1 CUDA_HOME=/usr/local/cuda nxgenesis    # CUDA 12.x
make USE_OPENCL=1 nxgenesis                            # OpenCL 1.2+
```

**With MPI (PGENESIS):**

```sh
cd ../../pgenesis/src && make install
sh ../regen_pgenesis_wrapper.sh    # see Building: the stock rule can emit a 0-byte wrapper
```

Then read [Building](#building) for the parts that bite — the CUDA linker step,
the empty PGENESIS wrapper, and why a GPU-enabled binary can refuse to start on
a compute node. If you only want to check the claims, skip all of it and run
[`reproduce/run_all.sh --quick`](#reproducing-the-benchmarks).

## Known issues

### Wrong results in the `v2.5` release, fixed after it

**If you ran the `v2.5` tag (or its Zenodo archive) with `chanmode=4`/`5` on a
model that uses synaptic channels, a `spike` element, GHK, or calcium
concentration pools, the results are wrong.** Re-run on current `master`.

The GPU kernels implement five opcodes and silently ignore any other — without
skipping its operands. The first unhandled opcode therefore desynchronises the
walk over the solver's `ops[]` program, and every later coefficient read lands
on a wrong index. `SPIKE_OP` carries two operands, so a soma with a `spike`
element is enough. There is no error message; membrane voltage is wrong from
the first step and typically diverges.

The detection for this already existed — `build_comp_index()` marked the
affected compartments — but the mask was computed and freed without ever being
consulted, and the CUDA port omitted it entirely.

It went unnoticed because every validation model in this repository uses only
`tabchannel` elements driven by `inject`, which never trips it. It shows up
immediately on a real network model: on the bundled
[`genesis/Scripts/VAnet2`](genesis/Scripts/VAnet2) (Vogels & Abbott 2005, as
published in Brette et al. 2007, ModelDB 83319) the CUDA backend produced
Vm = 1.5 V at t = 0 against a correct −0.065 V.

Fixed in commit `5027e73`: both backends now refuse such a model, print which
compartments are affected, and fall back to the CPU solver for that `hsolve`.
Verified byte-identical to the CPU reference over the full VAnet2 run.

**Unaffected:** models built only from `tabchannel` elements and driven by
`inject`, including every benchmark under `genesis/Scripts/benchmark/`. The
speedup figures below were measured on those and are not touched by this.

### The `v2.5` and `v2.5.1` tags report 2.4 in their banner (cosmetic, fixed in 2.5.2)

Binaries built from the `v2.5.1` tag — and from its Zenodo archive — print
`Release Version: 2.4 / Release Date: May 2019` at startup. The release, the tag
and the SoftwareX metadata table all say 2.5.1; only the banner disagreed.

`VERSIONSTR` and `VERSIONDATESTR` live in `genesis/src/sim/sim_version.h` and
had never been touched since the 2.4 May 2019 update. The Makefile's separate
`VERSION` variable, which names the install directory and the tarball, was 2.4
for the same reason. Both were corrected after the v2.5.1 tag, so **v2.5.2 is the first release whose binary reports its own version**.

**Nothing computational is affected** — no solver, kernel or model behaviour
depends on either string. It is recorded here because the archived artifact a
reader downloads will disagree with the version they were told to expect.

### A missing `include` corrupted the heap and never reported failure (fixed in 2.5.3)

Both `include` rules released their operands inside the not-found branch and then
fell through to code that used or released them again. `yyerror` reports; it does
not unwind. So a script naming a file that is not on `SIMPATH` left either a
dangling pointer in the parse tree, when compiling, or a double free otherwise,
and the interpreter continued from there in undefined behaviour.

What a user saw was never a clean error. With `-nox` and stdin on `/dev/null`, a
missing include alone exited 139 with a segmentation fault after printing the
message; the same after a successful include did likewise; and one followed only
by `quit` hung in `select()` until killed.

**The interpreter never exited with a usable non-zero status**, which in batch
work is expensive: a hung process looks exactly like a working one to a
scheduler, so a queue of simulations can spend its whole allocation on a script
that failed in its first second.

Fixed in `6fe3786`: the not-found branch now reports and frees nothing, and the
code below it releases each operand exactly once or hands it to the parse tree,
as it already did on the success path.

## Where the speedups come from

Two numbers are worth separating, because they answer different questions.
**Step-phase** times the simulation loop alone and measures what the kernel
can do; **end-to-end** wall-clocks the whole process, model construction
included, and is what you actually wait for. We quote both.

For single-compartment (isopotential) networks, a batched multi-step
"multiloop" kernel reaches <!--claim:singlecomp_cuda_a40_n50000-->21.0<!--/claim-->x (A40) and <!--claim:singlecomp_cuda_a100_n50000-->21.9<!--/claim-->x (A100) end-to-end at
N=50,000, matching the fp64 CPU reference to about 1e-7 V.

That kernel updates each compartment independently, which is only correct
for isopotential cells. Real dendritic trees need the Hines tridiagonal
elimination, so we added a second kernel, `hines_tree_eliminate`, that runs
the same elimination the CPU solver does, one GPU thread per neuron. On the
UMCS cluster, 10 replicates each, at N=50,000 neurons x 16 compartments that
is <!--claim:multicomp_step_a40_n50000-->37.3<!--/claim-->x (A40) and <!--claim:multicomp_step_a100_n50000-->80.8<!--/claim-->x (A100) step-phase, still climbing with N, but
<!--claim:multicomp_e2e_a40_n50000-->3.62<!--/claim-->x and <!--claim:multicomp_e2e_a100_n50000-->3.90<!--/claim-->x end-to-end. The gap is not a kernel deficiency: these runs are
only 200 steps, so the unaccelerated construction phase dominates, and the
end-to-end figure rises toward the step-phase ceiling as runs lengthen.

Against other simulators, on the Vogels-Abbott COBAHH network (4000 cells,
5 s, single-threaded CPU on one cluster node) GENESIS 2.5 runs the model as
published, one solver per cell, in <!--claim:vanet2_genesis_published_s-->46.9<!--/claim--> s against
<!--claim:vanet2_coreneuron_cpu_s-->76.5<!--/claim--> s for CoreNEURON and <!--claim:vanet2_neuron_cpu_s-->95.8<!--/claim--> s for NEURON 9.0.2, which is
<!--claim:vanet2_published_vs_coreneuron_cpu-->1.63<!--/claim-->x and <!--claim:vanet2_published_vs_neuron_cpu-->2.04<!--/claim-->x faster. Built with one solver per layer, the
form the paper uses, it takes <!--claim:vanet2_genesis_1solver_s-->33.2<!--/claim--> s: <!--claim:vanet2_vs_coreneuron_cpu-->2.30<!--/claim-->x and <!--claim:vanet2_vs_neuron_cpu-->2.89<!--/claim-->x. These wall
times were not saved as data when they were measured; the revision re-measures
every arm in one session. Both networks match in size,
connectivity, stimulation protocol and firing rate (26.8 vs 27.9 Hz); the
harness and the equivalence checks are in
[`cluster_bringup/coreneuron/`](cluster_bringup/coreneuron/).

Pushing that multi-compartment benchmark toward a Blue Brain Project-scale
population (~31,000 neurons) is what surfaced the O(n²) construction bug
mentioned above — before the fix, that model didn't finish building at all;
after, a 1.7-million-compartment, N=100,000 population builds in
<!--claim:construction_1700k_s-->51.5<!--/claim--> ± <!--claim:construction_1700k_s_sd-->0.6<!--/claim--> s.

<p align="center">
  <img src="paper/figures/fig10_multicompartment_speedup.png" alt="Multi-compartment GPU tree-elimination speedup vs. CPU on the UMCS A40 and A100, log-log, showing step-phase and end-to-end series for each card" width="600">
</p>

The methodology, the confounds we ran into and had to rule out, and the raw
numbers behind all of this are in the
[draft manuscript](paper/manuscript_softwarex_submission.pdf) and in
[`paper/docs/REPLICATION.md`](paper/docs/REPLICATION.md).

## Repository layout

| Path | Contents |
|---|---|
| `genesis/` | GENESIS 2.4 source (from the November 2014 public release) plus the OpenCL (`genesis/src/hines/opencl/`) and CUDA (`genesis/src/hines/cuda/`) backends and the `hines_tree_eliminate` kernel |
| `pgenesis/` | Official PGENESIS 2.4 (MPI) release |
| `genesis-binaries/` | Pre-compiled binaries (e.g. Cygwin) inherited from upstream |
| `cluster_bringup/` | Scripts to build, validate, and benchmark on a GPU cluster (used on UMCS A40/A100 nodes) |
| `experiments/` | Benchmark drivers, raw data, and plotting scripts behind the paper's figures |
| `paper/` | The manuscript, replication guide, figures, and design notes |

## Requirements

Linux, x86_64, GCC, GNU Make. Beyond that:

- OpenCL backend: an OpenCL 1.2+ runtime (we've used ROCm 6.3.1 and Mesa
  rusticl)
- CUDA backend: CUDA 12.x (tested with 12.8 on `sm_89`/RTX 4090,
  `sm_80`/A100, `sm_86`/A40)
- PGENESIS: an MPI implementation (MPICH/Hydra or Open MPI)

Neither GPU backend is required.

**The accelerator builds link their runtime hard.** A binary built with
`USE_OPENCL=1` needs `libOpenCL.so.1` at start-up and one built with
`USE_CUDA=1` needs `libcudart.so.<major>`; without them it does not fall back
to the CPU, it fails to start at all:

```
nxgenesis: error while loading shared libraries: libOpenCL.so.1:
cannot open shared object file: No such file or directory
```

On a cluster this bites in a specific way: the login node usually has the
driver libraries installed and the compute nodes often do not, so the same
binary runs interactively and dies the moment it is submitted. Point
`LD_LIBRARY_PATH` at a location visible from the nodes — e.g.
`LD_LIBRARY_PATH=/opt/cuda/lib64` — or build the plain CPU target for the
queue. If you never intend to use a GPU, build without either flag and the
question does not arise.

## Building

Plain CPU/MPI, same as GENESIS 2.4:
```sh
cd genesis/src
make clean; make; make install
```

OpenCL:
```sh
cd genesis/src
make USE_OPENCL=1 nxgenesis
```
This builds `hsolve`'s OpenCL kernels (`genesis/src/hines/opencl/ocl_channel.cl`)
into `nxgenesis` and links `-lOpenCL`. A run that actually reaches the GPU
prints a non-empty `OCL PROFILING SUMMARY` at exit; if it falls back to CPU
(no channels attached, or the kernel failed to build), that line is absent.

CUDA:
```sh
cd genesis/src
make USE_CUDA=1 CUDA_HOME=/usr/local/cuda nxgenesis
```
The CUDA kernels are a line-for-line port of the OpenCL ones behind the
same entry point, in fp32 by default and in fp64 with
`GENESIS_GPU_PRECISION=fp64` (one binary; see below). If both `USE_OPENCL` and `USE_CUDA` are defined, CUDA
wins. The linker step is the fiddly part: the default `EXTRALIBS` already
carries `sprng` and `TERMCAP`, and a bare `EXTRALIBS=-lcudart` will silently
drop both instead of adding to them. See
[`genesis/src/hines/cuda/BUILD_CUDA.md`](genesis/src/hines/cuda/BUILD_CUDA.md)
for the full invocation, or just use
[`cluster_bringup/10_build.sh`](cluster_bringup/10_build.sh), which also
picks the right `-arch` for whatever GPU it finds.

PGENESIS (MPI), after building GENESIS above:
```sh
cd pgenesis/src
make install
```

**Check that `pgenesis/bin/pgenesis` is not empty.** The stock install rule
produces a 0-byte wrapper on this tree, and a 0-byte wrapper silently removes
the `-nodes N` launch interface that the PGENESIS documentation and the
benchmark protocol both assume. Regenerate it with:

```sh
sh pgenesis/regen_pgenesis_wrapper.sh
```

which reproduces the same substitution the Makefile intends, but leaves the
path placeholders in so the wrapper self-locates instead of baking in the
machine it was generated on. The generated wrapper is `#!/bin/csh -f`, so the
host that *runs* it needs csh or tcsh installed — many current cluster images
do not have either. If csh is unavailable, launch the binary directly with
`mpirun -np <ranks> pgenesis/bin/Linux/nxpgenesis <script>.g`; the bare binary
does not accept `-nodes`, which is the whole reason the wrapper exists.

### If the build fails

Three failures account for nearly every build problem reported on this tree, and
all three are environment, not code. [`cluster_bringup/10_build.sh`](cluster_bringup/10_build.sh)
is a worked example that handles all of them.

**`cannot find -lfl` / `undefined reference to yywrap`.** Many distributions and
most cluster images ship the `flex` binary without `libfl`. GENESIS links its own
code generator `code_g` with `-lfl`, so the build dies before it can generate the
`*_g@.c` sources everything else needs. `libfl` supplies one function here;
build a stub and point `LEXLIB` at it:

```sh
mkdir -p locallib
printf 'int yywrap(void){return 1;}\n' > locallib/yywrap.c
gcc -c locallib/yywrap.c -o locallib/yywrap.o
ar rcs locallib/libfl.a locallib/yywrap.o
make LEXLIB="$PWD/locallib/libfl.a" nxgenesis
```

Pass the same `LEXLIB=` to every later `make`, including `bindist`. A `.a` is
what the link expects — a bare `.o` is not a drop-in replacement here.

**A fresh clone did not build between 2026-08-24 and v2.5.3. Fixed in v2.5.3.**
`make genesis` and `make nxgenesis` stopped with

```
No rule to make target 'diskio/interface/netcdf/netcdflib.o', needed by 'genesis'
```

The top-level `libs` step entered `diskio/` but never descended into
`diskio/interface/netcdf/`. The cause was a tracked stamp file:
`genesis/src/diskio/interface/fflibs` is the zero-length marker the `fflibs` rule
touches after building its subdirectories, and it was committed to the
repository — so a fresh clone arrived with the stamp already newer than its
prerequisites and make skipped the rule that builds the subdirectories.

A tree that had been built before never hit this, because its objects survived
from the earlier build. That is exactly why it went unnoticed for two months.

Fixed in `aa163c5` by untracking the stamp. If you are on v2.5.2 or earlier and
hit this, `rm genesis/src/diskio/interface/fflibs` before building.

**`make clean` makes it worse before it makes it better.** Some generated
`*_g@.c` files are tracked and some are not, so an incremental build can succeed
on a machine where a clean one fails: `clean` deletes the generated sources, and
regenerating them needs `code_g`, which needs the fix above. If a build that
worked yesterday fails today, check whether something ran `clean`.

**`EXTRALIBS=` replaces, it does not append.** The default is
`$(SPRNGLIB) $(TERMCAP) $(GPULIBS)`. Passing `EXTRALIBS=-lcudart` silently drops
sprng and the terminal libraries with it. Pass the full set, as
`10_build.sh` does.

Two smaller ones worth knowing. `make clean` does not touch `hines/cuda/`, so a
stale object built for a different GPU architecture links fine and fails at run
time with *"no kernel image is available for execution on the device"* — remove
`hines/cuda/*.o hines/hineslib.o` by hand when switching cards. The start-up segfault inside `tset()` is **fixed in 2.5.4**, and the advice
that used to stand here — prefer an older compiler — was wrong. The toolchain
had nothing to do with it: `AvailableCharacters()` returned an uninitialised
stack slot whenever `ioctl(FIONREAD)` failed, which it does on any stdin that
is not a character device, `/dev/null` included. Whether that garbage was large
enough to walk off the end of `tset()`'s 1000-byte buffer depended on the size
of the environment block, which is why the same source crashed on one machine
and ran on the next.

## Using the accelerator backends

Both backends kick in automatically for any `hsolve` element using
`chanmode=4` (or `5`) with real ion-channel state — no model changes needed.
A tree with more than one compartment goes to `hines_tree_eliminate`;
single-compartment networks use the cheaper per-compartment multiloop kernel.
A few environment variables control dispatch at run time:

| Variable | Effect |
|---|---|
| `GENESIS_CUDA_GRAPH=0` or `1` | CUDA Graph dispatch. Unset (the default): on for the batched tree loop, where it is 1-6% faster with identical results, off for the per-step dispatch of spiking networks, where it gains nothing. `0` turns it off everywhere, `1` on everywhere. Measurements: `cluster_bringup/logs/cuda_graph_decision_20261002.md` |
| `GENESIS_GPU_PRECISION=fp64` | Run the kernels in double precision, as the CPU solver does. The default, `fp32`, is what every published figure used and runs on integrated GPUs without double precision. A device without it refuses `fp64` with a message and the model runs on the CPU. The start-up line names the precision in use |
| `GENESIS_OCL_MULTILOOP=<K>` | Batch `K` steps into one OpenCL dispatch instead of one per step |
| `GENESIS_CUDA_MULTILOOP=<K>` | Same, CUDA |
| `GENESIS_OCL_TREE_MAX_NCOMPTS=<N>` | Safety cap for laptop integrated GPUs, which can hang past ~22,000-24,000 compartments when the same chip also drives the display. Confirmed not to affect dedicated GPUs (verified on A40 well beyond that size), so set `0` on any datacenter or desktop card |

**If you run multi-compartment models larger than 20,000 compartments on a
dedicated GPU, set `GENESIS_OCL_TREE_MAX_NCOMPTS=0`.** That cap defaults to
20,000, and above it the batched tree solver declines the model and falls back
to per-step dispatch. The run still produces correct results, but much more
slowly -- at 800,000 compartments the difference measured 3-7x, larger on the
faster card, because the per-step launch overhead is fixed. The fallback prints
a line to stderr, which is easy to lose in a batch script that redirects it.

The kernel-selection logic is in the manuscript's "Software architecture"
section; the derivation of `hines_tree_eliminate` itself, including the
dead ends, is in
[`genesis/src/hines/GPU_HINES_SOLVE_DESIGN.md`](genesis/src/hines/GPU_HINES_SOLVE_DESIGN.md).

## Why "2.5" and not "3.0"

"GENESIS 3" was a separate modularization effort that ended up as several
independent successors (Neurospaces/Heccer, MOOSE) rather than a drop-in
replacement for GENESIS 2.4. This isn't that. GENESIS 2.5 doesn't
re-architect anything — it's meant for people already running GENESIS 2.4
who want GPU acceleration without touching their models or scripts.

## Citing this work

See [`CITATION.cff`](CITATION.cff). Until the SoftwareX manuscript is
accepted, cite the repository directly:

```
Chlasta K, Wójcik GM. GENESIS 2.5: optimisation and opt-in OpenCL/CUDA
acceleration for the GENESIS/PGENESIS compartmental neural simulator. v2.5.4, 2026.
https://github.com/WarsawIQ/genesis-2.5
Archived: https://doi.org/10.5281/zenodo.22032886
```

## About the base GENESIS 2.4 / PGENESIS 2.4

`genesis/` is GENESIS 2.4 as of the May 2019 update
(`genesis-pgenesis-2.4-05-2019.tar.gz` on
[genesis-sim.org](http://genesis-sim.org/GENESIS)), plus later fixes
(facilitation/depression synapse objects, extracellular field-potential
calculation, glibc build fixes, Python 2/3 support in the analysis scripts).
`pgenesis/` is the official PGENESIS 2.4 release. If you just want those
upstream fixes without the accelerator backends, drop these files into an
existing GENESIS 2.4 install and rebuild as above.

## License

GPL v2 (program) / LGPL v2.1 (library portions) — see
[`LICENSE`](LICENSE), [`Licence.txt`](Licence.txt), and
[`genesis/COPYRIGHT`](genesis/COPYRIGHT). Everything added for 2.5 (the
accelerator backends, benchmark scripts, `paper/`) is under the same terms.

## Acknowledgements

Thanks to the Maria Curie-Skłodowska University (UMCS) in Lublin and the
LubMAN UMCS computing centre for access to the "Lunar" cluster's A100 and A40
nodes, and to WarsawIQ for the AMD Radeon 890M and RTX 4090 used for the
laptop- and desktop-class benchmarks. Full acknowledgements are in the
manuscript.

## Contact

Karol Chlasta — karol@chlasta.pl
