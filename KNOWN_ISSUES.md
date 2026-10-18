# Known issues

Every defect found after a release, newest first, with the versions it affects
and where it is fixed. Build problems are in [docs/BUILDING.md](docs/BUILDING.md).

| Issue | Affects | Fixed in | Effect |
|---|---|---|---|
| [readcell crashes on a cell whose compartments have coordinates; re-creating an element duplicates it](#the-element-tree-in-v25v261-fixed-in-262) | v2.5 to v2.6.1 | 2.6.2 | a crash when the model is read; no wrong number reported |
| [A long OpenCL single-compartment batch resets an integrated GPU under rusticl](#opencl-a-long-single-compartment-batch-can-reset-an-integrated-gpu-fixed-in-261) | 2.6.0 | 2.6.1 | the run is lost; no wrong result |
| [Table 2's GPU arms ran 10 steps fewer than the CPU arm](#table-2s-gpu-arms-ran-10-steps-fewer-than-the-cpu-arm-002-fixed-in-261) | 2.6.0 benchmark harness | 2.6.1 | 0.02% of the work; no published speedup moves |
| [Spiking networks on the GPU: spurious first-step spikes, state kept across RESET, stale HGET/HPUT](#spiking-networks-on-the-gpu-in-v251v254-fixed-in-260) | v2.5.1 to v2.5.4 | 2.6.0 | **wrong results** for spiking networks on CUDA; reruns after RESET on both backends |
| [Models the kernels cannot compute were computed anyway](#wrong-results-in-the-v25-release-fixed-in-251) | v2.5 | 2.5.1 | **wrong results** with synaptic channels, `spike`, GHK or concentration pools |
| [A missing `include` corrupts the heap and never reports failure](#a-missing-include-corrupted-the-heap-and-never-reported-failure-fixed-in-253) | up to v2.5.2 | 2.5.3 | a hung or crashed batch job, never a clean error |
| [The binary reports version 2.4](#the-v25-and-v251-tags-report-24-in-their-banner-fixed-in-252) | v2.5, v2.5.1 | 2.5.2 | cosmetic |

## The element tree in v2.5–v2.6.1 (fixed in 2.6.2)

**If you read a cell with `readcell` and its compartments have coordinates (any
branched cell from a `.p` file in cartesian or polar form), GENESIS 2.5 up to
2.6.1 crashes**, usually while reading the cell. The constant-time `Attach()` of
2.5 added a tail pointer, `childtail`, to the generic element layout but not to
the layout compartments use, so a compartment's link to its next sibling lay on
its own `x0`/`y0` coordinates: setting them broke the element tree, and adding a
sibling overwrote them. Three smaller defects came with the same change:
`readcell`'s `*makeproto` left the new tail pointers and the element hash table
pointing at a freed element (a crash on the next child created under the
prototype); an element made outside `create`, such as `/output` at start-up, was
missing from the hash table, so creating it again appended a second element of
the same name where GENESIS 2.4 replaced it; and two hash lookups copied
pathnames into 300-byte buffers.

We know of no model in which this changed a computed number instead of crashing,
though a script that set and later read a compartment's `x0`/`y0` could have read
corrupted coordinates. The campaign's models build their compartments by script, and
VAnet2's single compartment sits at 0,0,0, so no number of the SoftwareX paper is
affected; v2.6.2's output is byte-identical to v2.6.0's in fp32 on the A40 and
the A100 (`cluster_bringup/logs/verify_against_base/`). All four were found from
GitHub Copilot's review of genesis-sim/genesis-2.4#7, which carries the same
construction code, and are covered by `genesis/Scripts/tests/run_tests.sh`
(element_layout.g, readcell_coords.g, makeproto.g, duplicate_element.g,
long_paths.g), which `reproduce/run_all.sh` and CI run on every push.

## OpenCL: a long single-compartment batch can reset an integrated GPU (fixed in 2.6.1)

**Fixed on `dev-2.6.1` (12c1cb3).** On a device with host-unified memory the
multiloop runs in dispatches of about `GENESIS_OCL_DISPATCH_MS` (default 500 ms),
bit for bit the result of one dispatch; a discrete GPU keeps one dispatch. Checked
by `cluster_bringup/campaign/ocl_chunk_check.sh` on the Radeon 890M
(`cluster_bringup/logs/campaign_prep/ocl_chunk_check_victor_20261011_174433.txt`):
E9's reset case completes under rusticl in 46 dispatches with no ring timeout.
What follows describes 2.6.0.

**What happens.** With `GENESIS_OCL_MULTILOOP=<K>` the OpenCL backend runs a
single-compartment network for all K steps in one kernel dispatch. Under Mesa
rusticl, which submits to the graphics queue, the amdgpu driver resets the GPU
when one dispatch runs longer than its lockup timeout (10 s by default). On the
AMD Radeon 890M the network of 50 000 cells over 50 000 steps triggers this in
every attempt; the display may flicker while the GPU recovers. ROCm submits to a
compute queue and completes the same run in 5.7 s.

**Evidence.** E9 on v2.6.0-rc4:
`cluster_bringup/logs/campaign_v2.6.0-rc4/E9_victor_20261011_044551*` (the
rejected `t1_rusticl_n50000` runs, and the kernel log with the ring timeouts and
resets), and the per-step run that completes:
`cluster_bringup/logs/campaign_prep/e9_rusticl_perstep_victor_20261011_045317/`.

**Until it is fixed.** Under rusticl, run long single-compartment models without
`GENESIS_OCL_MULTILOOP` (one dispatch per step; it completes, but on the 890M it
is slower than the CPU), or use ROCm.

**Why not in 2.6.0.** The batched tree dispatch already has a cap on integrated
GPUs (`GENESIS_OCL_TREE_MAX_NCOMPTS`, 20 000 compartments); the single-compartment
multiloop has none, and it cannot be split from the outside: a smaller
`GENESIS_OCL_MULTILOOP` than the run length makes the remaining steps no-ops
(`ocl_chip_update` in `genesis/src/hines/opencl/ocl_hsolve.c`). A fix changes the
GENESIS sources, which for 2.6.0 are frozen at v2.6.0-rc4, the tag every number
of the SoftwareX paper was measured on (decided 2026-10-11).

**Plan for 2.6.1.**
- Split the multiloop into dispatches of at most M steps inside
  `ocl_multiloop_dispatch`, keeping vm and the gating state on the device
  between them, so the result is byte-identical to one dispatch.
- Choose M from the device: on a device that drives a display (or under
  rusticl), keep one dispatch well under the lockup timeout; elsewhere keep
  today's single dispatch. Allow an override, as `GENESIS_OCL_TREE_MAX_NCOMPTS`
  does for trees.
- Tests: the 80_accel_regression golden must not change (fp32 byte-identical);
  E9's `t1_rusticl_n50000` arm must complete with no ring timeout in the kernel
  log.

## Table 2's GPU arms ran 10 steps fewer than the CPU arm (0.02%; fixed in 2.6.1)

**Fixed on `dev-2.6.1` (b9820fb):** E3 and E9 set K = N + 10, and the benchmark's
comment says why. What follows describes 2.6.0.

`hh_spiking_benchmark.g` does `reset`, `step 10` (a warm-up) and `step N`. A
single-compartment multiloop of K steps runs all K at the first solver call,
which is the first warm-up step, and makes every later call a no-op. E3 (Table 2 of
the revised paper)
and E9 set K = N, so their GPU arms ran N steps where the CPU arm ran N + 10. The
kernels are not at fault: with K = N + 10 the OpenCL multiloop in fp64 prints the
CPU's final voltage to every digit
(`cluster_bringup/logs/campaign_prep/multiloop_offset_victor_20261011_142935.csv`,
`cluster_bringup/campaign/multiloop_offset_check.sh`). With N = 50 000 the CPU did
0.02% more work, which moves no Table 2 speedup at the precision printed (their
standard deviations are 1-2%). The dendritic-tree arms set K + 10 and are not
affected. The script's comment, which attributes the different final voltages
to fp32, is wrong.

**Plan for 2.6.1.** E3 and E9 set K = N + 10 as `tree_rep` does, and the
benchmark's comment says why the final voltage depends on K.

## Spiking networks on the GPU in v2.5.1–v2.5.4 (fixed in 2.6.0)

**If you ran a spiking network on CUDA with one of the `v2.5.1` to `v2.5.4` tags,
every cell fired a spurious spike in the first step**: when the device also
solved the cable equation it never received the initial membrane potentials. In
the same releases the CUDA and OpenCL backends kept their device state across
`RESET` (a second run started where the first had ended), and `HGET`/`HPUT` read
and wrote the host's stale copy instead of the device's. All three are fixed in
2.6.0 and checked on every backend by
`genesis/Scripts/benchmark/hh_reset_rerun_check.g` and
`cluster_bringup/campaign/spike_start_check.sh`. `v2.5` itself is not affected
by the first.

## Wrong results in the v2.5 release (fixed in 2.5.1)

**If you ran the `v2.5` tag (or its Zenodo archive) with `chanmode=4` or `5` on a
model that uses synaptic channels, a `spike` element, GHK or calcium
concentration pools, the results are wrong.** Rerun on a current release.

The GPU kernels implement five opcodes and ignored any other without skipping
its operands. The first unhandled opcode therefore desynchronised the walk over
the solver's `ops[]` program, and every later coefficient read landed on a wrong
index. `SPIKE_OP` carries two operands, so a soma with a `spike` element was
enough. There was no error message; the membrane voltage was wrong from the
first step and typically diverged. On the bundled
[`genesis/Scripts/VAnet2`](genesis/Scripts/VAnet2) (Vogels and Abbott 2005, as in
Brette et al. 2007, ModelDB 83319) the CUDA backend produced Vm = 1.5 V at t = 0
against a correct -0.065 V.

The detection already existed (`build_comp_index()` marked the affected
compartments) but the mask was computed and freed without being consulted, and
the CUDA port omitted it. It went unnoticed because every validation model then
in the repository used only `tabchannel` elements driven by `inject`.

Fixed in `5027e73`: both backends refuse such a model, print which compartments
are affected, and leave that `hsolve` to the CPU solver; the result is
byte-identical to the CPU reference over the full VAnet2 run. Models built only
from `tabchannel` elements and driven by `inject` were not affected.

## A missing `include` corrupted the heap and never reported failure (fixed in 2.5.3)

Both `include` rules released their operands inside the not-found branch and then
fell through to code that used or released them again. `yyerror` reports; it does
not unwind. A script naming a file that is not on `SIMPATH` therefore left a
dangling pointer in the parse tree, when compiling, or a double free otherwise,
and the interpreter went on in undefined behaviour. With `-nox` and stdin on
`/dev/null`, a missing include exited 139 with a segmentation fault after
printing the message, and one followed only by `quit` hung in `select()` until
killed. The interpreter never exited with a usable non-zero status, so in a
batch queue a hung process looked like a working one.

Fixed in `6fe3786`: the not-found branch reports and frees nothing, and the code
below it releases each operand exactly once or hands it to the parse tree, as
the success path already did.

## The v2.5 and v2.5.1 tags report 2.4 in their banner (fixed in 2.5.2)

Binaries built from these tags, and from their Zenodo archives, print
`Release Version: 2.4 / Release Date: May 2019` at start-up. `VERSIONSTR` and
`VERSIONDATESTR` in `genesis/src/sim/sim_version.h`, and the Makefile's
`VERSION`, had not been touched since the 2.4 update of May 2019. Nothing
computational depends on either string.
