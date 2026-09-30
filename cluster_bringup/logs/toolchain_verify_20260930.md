# Toolchain rebuild from nothing, 2026-09-29/30

Every external tool the comparisons use was rebuilt on the UMCS cluster in an empty
directory (`WORK_DIR=$HOME/tc-verify-20260929`), using only the scripts in
`cluster_bringup/toolchains/` and `cluster_bringup/coreneuron/`, nothing from the home
directory where the paper's builds were made.

| Step | Result | Time |
|---|---|---|
| `fetch_modeldb_83319.sh` | checksum OK | 1 s |
| `10_miniforge.sh` | Miniforge 26.3.2-3, Python 3.13.13 | 38 s |
| `20_nvhpc.sh` | NVHPC 24.11 (6.1 GB download) | 1685 s |
| `30_neuron_gpu.sh` | failed twice, then OK (see below) | 913 s |
| `40_arbor_gpu.sh` | Arbor 0.10.0, CUDA, icelake-server | 123 s |
| `prepare_cobahh.sh` | patch applied, ncell 4000 | 0 s |
| `build_mechanisms.sh` | CPU OK; GPU failed once, then OK | 20 s |

Build host: miranda, 48 cores. Times are wall clock of each recipe.

## What the rebuild found

The recipes were written from the scripts that had built the originals, and the rebuild
showed three things those scripts had been getting right by accident:

1. **Generator order (30_neuron_gpu.sh).** Copying the GCC-built `nocmodl` and `nmodl` into
   the GPU tree before building does not keep them: make relinks both with nvc++, and that
   `nocmodl` segfaults on every `.mod` file. The original build had failed, been patched and
   resumed, which put the steps in the right order. Fixed in 93034a2.
2. **"Already built" check (30_neuron_gpu.sh).** Testing for the binaries accepted the failed
   build on the second run, since a half-built tree has them. A stamp written at the end now
   decides. Fixed in 5468eb9.
3. **NRNHOME (build_mechanisms.sh).** The NEURON build is used uninstalled; `nrnivmodl` then
   looks for its makefile under `/usr/local` unless `NRNHOME` is set. The original had been
   installed. Fixed in the commit that adds this file.

## Functional check on the rebuilt tools

Run on inf02 (A40); the A100 on inf03 was in use by another service. These are checks that
the rebuilt tools work and compute the same thing, not measurements for the paper.

- `arbor_check.sh` on inf02 and inf03: Arbor 0.10.0 with CUDA from the rebuilt prefix.
- CoreNEURON GPU (`coreneuron_gpu_standalone.sh`), 3 runs on the A40: 4000 cells, `tstop`
  5000 ms, **592 865 spikes in every run, identical to the paper's A100 runs
  (`cn_gpu_r1.log`)**; wall 26.74, 26.53, 26.47 s (the paper's A100: 27.0 ± 0.1 s).
- Arbor GPU, N = 10 000 × 16 compartments, K = 5000 on the A40: 2.52 s wall against
  2.48–2.51 s in `crossover_inf02_20260820_131248.csv`.

Not yet done: the same two checks on the A100, for comparison with the Table 5 and Table 7
times directly. They wait for the card to be free.
