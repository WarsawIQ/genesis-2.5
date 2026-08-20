# Reproducing the paper's results

One command:

```sh
sh reproduce/run_all.sh --quick        # ~15 min, the accelerator claims
sh reproduce/run_all.sh                # ~95 min, adds the sweeps and the spiking network
sh reproduce/run_all.sh --with-neuron  # adds the cross-simulator comparison
```

It builds GENESIS, checks the accelerator against the CPU solver, measures the
speedups, regenerates the figures from what it just measured, and prints each
published number beside yours with a verdict:

```
claim                     table            published    measured    delta  verdict
correctness_fp32          text                 1e-07       7e-08  7.0e-08  ok
ksweep_k5000              tab:mcksweep            57        55.2      -3%  ok
vanet2_1solver_speedup    tab:coreneuron        1.43        1.41      -1%  ok
```

## What you need

Linux x86_64, GCC, GNU make, a CUDA 12.x toolkit and an NVIDIA GPU. Set
`CUDA_HOME` if `nvcc` is not on your `PATH`. `--with-neuron` also wants NEURON
9.x (`pip install neuron`); the Arbor arms additionally need an Arbor built with
CUDA, since the published wheels are CPU-only.

Nothing here needs root, a scheduler, or the UMCS cluster.

## Where each result in the paper comes from

| in the paper | reproduced by | needs |
|---|---|---|
| Fig. 1, fp32 against fp64 | `stages/10_correctness.sh` | GPU |
| Table 2, single-compartment speedups | `stages/20_speedup.sh` | GPU |
| Table 3 and Fig. 2, multi-compartment sweep | `stages/20_speedup.sh` (full mode) | GPU |
| Table 4, K-sweep | `stages/20_speedup.sh` | GPU |
| Table 5 and Fig. 4, GENESIS arms | `stages/50_spiking.sh` | CPU + GPU |
| Table 5 and Fig. 4, NEURON arms | `cluster_bringup/coreneuron/verify_cn.sh` | NEURON 9.x |
| Table 5, Arbor arm | `cluster_bringup/arbor_vanet2/` | Arbor with CUDA |
| Table 6 and Fig. 5, crossover | `stages/30_crossover.sh` | GPU, and Arbor for the crossing itself |
| Fig. 6, membrane potentials agree | `paper/scripts/compare_vm_traces.py` over `cluster_bringup/logs/vmcross/` | nothing |
| Fig. 3, construction scaling | `paper/scripts/plot_construction_scaling.py` over the shipped CSVs | nothing |

Two rows are out of this pack's reach and are documented rather than automated.
**CoreNEURON on the GPU** needs the NVHPC compiler and a rebuild of NEURON; the
procedure, the two failures it runs into, and the raw logs are in
`cluster_bringup/coreneuron/README.md` and `cluster_bringup/logs/cn_gpu_r*.log`.
**The A40 arm of the crossover** needs that card; the sweep script is
`cluster_bringup/coreneuron/crossover_sweep.sh` and its output is
`cluster_bringup/logs/crossover_inf02_20260820_131248.csv`.

## What is checked, and what merely follows

**The numbers are the claims**, so those are what `compare.py` checks against
`expected.csv`. **The figures follow from them** -- the plotting scripts under
`paper/scripts/` read the CSVs this pack writes, so you get the paper's figures
drawn from your own hardware rather than ours. That is a stronger check than
matching numbers alone, because it shows the same shape, not just the same
endpoint.

## Your numbers will differ, and that is expected

Absolute timings track the host CPU, the card model, and how warm the card is.
Tolerances in `expected.csv` are set accordingly, and what should reproduce is
the shape of each result: which arm wins, and roughly by how much.

Four things move results enough to be worth knowing about, all of them found the
hard way while producing this paper:

**A binary built for another card.** With no PTX in it the kernels will not
launch; with PTX they are JIT-compiled and run at a fraction of the speed while
still being timed as "GPU". An A100 once measured 278.9 s against an expected
4.6 for exactly this reason. `run_all.sh` checks the binary against the card
before timing anything and warns if they disagree; rebuild with `ARCH=sm_XX`.

**A GPU shared with another job.** A foreign process on the card once raised
every GPU figure by ~30% while leaving the CPU arm untouched, and the speedup
curve stayed smooth and entirely plausible. `run_all.sh` warns if the card is
already in use; heed it.

**A cold card.** The first run after the GPU has been idle is 1.2-1.8x slower
than a warm one. The pack takes several replicates for this reason. Do not
compare one short run against a published campaign.

**`GENESIS_OCL_TREE_MAX_NCOMPTS`.** Above 20,000 compartments the batched tree
solver otherwise declines the model and falls back to per-step dispatch, which
is a different code path and looks like a 3-7x GPU slowdown. `run_all.sh` sets
it; if you run the benchmarks by hand, set it too.

## Two results depend on the card, not just on the software

The crossover with Arbor falls at K ~ 6,400 steps on an A100 and at K ~ 1,800 on
an A40, because our kernel is fp32 where Arbor computes in double and the A40's
double-precision throughput is a fraction of the A100's. `stages/30_crossover.sh`
reads the card and records the crossing under the matching claim, so a run on an
A40 is not scored against the A100 figure.

The spiking network reaches parity between CPU and GPU rather than a speedup. A
zero-delay network exchanges spikes every step, so batching does not apply and
each step pays a dispatch. Reproducing parity is the expected outcome, not a
failure.

## If a claim lands outside tolerance

Check `nvidia-smi` for other jobs, re-run, and compare the *ratios* rather than
the absolute seconds. A number outside tolerance on different hardware is
usually hardware. If the ordering itself inverts -- the CPU arm beating the GPU
at large N, say -- that is worth reporting to karol@chlasta.pl.

## Layout

| path | what it is |
|---|---|
| `run_all.sh` | the entry point |
| `stages/` | one script per claim group, runnable on their own |
| `expected.csv` | published values and tolerances |
| `compare.py` | measured against published, with a verdict |
| `results/` | written by the run: CSVs, logs, `summary.csv` |

Each stage takes the results directory as its only argument, so any one of them
can be run on its own:

```sh
mkdir -p reproduce/results
sh reproduce/stages/50_spiking.sh reproduce/results
```

The underlying benchmarks live in `cluster_bringup/`, and the cross-simulator
harness, including how the NEURON and Arbor models were matched to the GENESIS
one and why that matching had to be verified rather than assumed, in
`cluster_bringup/coreneuron/README.md`.
