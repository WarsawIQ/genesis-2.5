# GENESIS 2.6.0

The release of the SoftwareX revision (SOFTX-D-26-01093). Its GENESIS and PGENESIS
sources are those of v2.6.0-rc4, on which every number of the revised paper was
measured.

## What is new

- **Precision chosen at run time.** CUDA and OpenCL kernels are built for both
  float and double; `GENESIS_GPU_PRECISION=fp32|fp64` selects them when the run
  starts. The default stays fp32, and its output is byte-identical to v2.5.4. A
  device without double precision (Mesa rusticl on the Radeon 890M, for example)
  refuses fp64 with a message and computes on the CPU.
- **CUDA Graphs.** The batched tree loop is dispatched as a CUDA Graph by
  default; `GENESIS_CUDA_GRAPH=1` turns graphs on for the per-step path too,
  `=0` turns both off. Results are identical with and without graphs.
- **Model switches for long runs and mixed tree sizes** in the benchmark and
  network scripts (GENESIS_VANET2_TMAX, GENESIS_VANET2_SEED, the mixed-tree
  variables of hh_multicompartment_createmap.g). Unset, every script behaves as
  before.

## Fixes

Three defects in the accelerated solvers, present since v2.5.1 (v2.5 is not
affected), found by the long spiking-network comparison of the SoftwareX
revision:

- CUDA, when the device also solves the cable equation (the single-compartment
  solve added in v2.5.1), never uploaded the initial membrane potentials, so
  every cell of a spiking network fired in the first step.
- CUDA and OpenCL kept their device state across `RESET`: a second run started
  where the first had ended.
- `HGET`/`HPUT` did not synchronise with the device, so a script reading a
  voltage got the host's stale copy.

The checks that found them run on every backend:
`genesis/Scripts/benchmark/hh_reset_rerun_check.g` and
`cluster_bringup/campaign/spike_start_check.sh`.

## Behaviour to know about

- With zero axonal delay, the CUDA solver delivers a spike to its targets at the
  next step; the CPU solver delivers it within the step to the cells after the
  sender in its loop. Spike trains of the two therefore part within a few
  milliseconds in a chaotic network and must be compared statistically; the CPU
  differs from itself by as much under another update order (see the paper,
  Section 3, and `cluster_bringup/campaign/spike_variability_check.sh`).
- On an integrated GPU the OpenCL backend declines batched tree dispatches above
  20 000 compartments (driver watchdog); `GENESIS_OCL_TREE_MAX_NCOMPTS`
  overrides the cap.
- Known issue: the single-compartment multiloop (`GENESIS_OCL_MULTILOOP`) runs
  the whole simulation in one dispatch and has no such cap. Under Mesa rusticl,
  which uses the graphics queue, a long batch (50 000 cells x 50 000 steps on the
  Radeon 890M) exceeds the driver's lockup timeout and the GPU is reset. Run such
  models without `GENESIS_OCL_MULTILOOP` under rusticl, or use ROCm. Fix planned
  for 2.6.1 (KNOWN_ISSUES.md).

## Measurement

Every number in the SoftwareX paper comes from one tag, v2.6.0-rc4, measured on
the UMCS cluster (A40, A100) and an AMD Radeon 890M laptop, and is regenerated
from the raw data in `cluster_bringup/logs/` by `reproduce/make_numbers.py`.
Note for anyone comparing with earlier figures: up to rc3 the CPU reference for
the dendritic-tree speedups ran hsolve in chanmode 1; from rc4 it runs in
chanmode 4, the mode of the GPU arms, which computes the same voltages about 4x
faster. The largest end-to-end speedup is therefore 24x on the A100 (it was
reported as 114x against chanmode 1).

## Verified

- Freeze gate against ce21b63, whose GENESIS sources are v2.5.4's: fp32 byte-identical on the A40 and the
  A100 with CUDA (graphs off and on) and OpenCL; fp64 within 1e-10 V of the CPU
  solver (`cluster_bringup/logs/verify_against_base/`).
- CI: CPU-only reproduction, claim map and harness tests on every commit.

## Binaries

`genesis-2.6.0-linux-x86_64.tar.gz` holds the three binaries the paper was measured
with (built from v2.6.0-rc4 on the UMCS cluster, AlmaLinux 8.10, glibc 2.28):
`nxgenesis_nocl` (CPU), `nxgenesis_ocl` (OpenCL 1.2) and `nxgenesis` (CUDA 12), with
`startup/`. Its `README.txt` lists the libraries each needs and the GPU code the CUDA
binary carries; `SHA256SUMS` inside and `cluster_bringup/logs/release/v2.6.0/manifest.txt`
in the repository give the checksums. Building from source is described in the README.
