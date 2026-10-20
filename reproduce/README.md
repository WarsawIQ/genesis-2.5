# Reproducing the paper's numbers

Every number in the revised paper was measured by the stages in
[`cluster_bringup/campaign/`](../cluster_bringup/campaign/) on release v2.6.0
(its release candidate rc4, same sources) and is computed from the raw data in
this repository by [`make_numbers.py`](make_numbers.py). `run_all.sh` runs the
same stages on your machine and computes the same numbers from what they
measured, with the same code:

| command | needs | measures | time on our machines |
|---|---|---|---|
| `sh reproduce/run_all.sh --cpu-only --quick` | Linux, GCC, make, flex, bison, ncurses, Python 3 | model construction up to 272 000 compartments, the CPU solver's modes, the action potential check, the gain from one solver per layer (Table 3's two GENESIS CPU rows) | 3 min with the build (laptop) |
| `sh reproduce/run_all.sh --cpu-only` | the same | construction up to 1.7 million compartments, more replicates | 13 min (laptop) |
| `sh reproduce/run_all.sh --quick` | an NVIDIA GPU, CUDA 12.x | adds Table 2, the speedup at K = 1000 and 10 000 steps, the tree threshold of Table 4, CUDA Graphs on the tree loop | 14 min with the build (A100): 14 numbers |
| `sh reproduce/run_all.sh` | the same | adds the paper's full sizes, the work imbalance and the 10 s spiking run | 66 min after the build (A100): 33 numbers |
| `... --with-simulators` | NEURON, CoreNEURON and Arbor, built by [`cluster_bringup/toolchains/`](../cluster_bringup/toolchains/) | adds Table 3 and the crossover with Arbor (Fig. 4) | about 1.5 h more (the campaign's E1 and E4) |

The CPU-only path also runs in a container with nothing installed, in CI on
every push (the quick sizes), and as the paper's Code Ocean capsule
([`codeocean_run.sh`](codeocean_run.sh), the full sizes):

```sh
docker build -t genesis25-cpu . && docker run --rm genesis25-cpu
```

## What it does

`run_all.sh` builds GENESIS, runs the action potential check (8 neurons under
one solver must fire the same action potential: the Hines-solver fixes), and
then runs the campaign stages in a reader's mode: `CAMPAIGN_DRY=1`,
`REPRO=quick` or `full`, and every file under `reproduce/results/`, so your data
never mix with the paper's. The stages keep the checks they had on the cluster:
a GPU in use by another job is waited for and then refused, the start-up banner
must name the backend and the precision asked for, a binary without code for
your card is refused, each arm has a discarded warm-up run, replicates
interleave the arms, and a run that did not do its work is rejected and retried
once.

[`measure.py`](measure.py) then takes every number the manuscript prints, swaps
its data file in [`claims.csv`](claims.csv) for your file of the same experiment,
and runs the extractor that computed the published value. On the CPU-only quick
path the end of the output looks like this (our laptop, 17 October 2026):

```
number                     in the paper          published       yours  verdict
-----------------------------------------------------------------------------------
cpu_cm1_over_cm4_trees     Section 3             4.2            3.9  ok
cpu_cm4_over_cm3_trees     Section 3             1.08          1.10  ok
e3c_construction_exponent  Section 4, Fig. 5     1.02          1.02  ok

3 numbers measured: 3 ok, 0 outside tolerance; ...

not measured by this run, and what they need:
   16  a full GPU run (run_all.sh)
   14  a GPU run (run_all.sh --quick)
   ...
```

**Verdicts.** A number that does not depend on the machine (the construction
exponent, the CPU's membrane potential) is checked against its tolerance in
`claims.csv`. A GPU number is checked the same way on an A40 or an A100, the
cards of the paper; on any other card only its shape is checked: a speedup must
stay on the same side of 1. The ratios of the CPU solver's modes are checked by
their shape too, because they depend on the processor: chanmode 1 takes 4.2
times as long as chanmode 4 on inf03, 4.0 on our laptop and 2.0 on GitHub's
runners. A ratio within its own tolerance of 1 (chanmode 3 against 4, at 1.08)
has no side on a machine where the two are equally fast, and is printed for
information, as are absolute times. `python3 reproduce/measure.py --self-test` lays our
own data out as a reader's run and requires every published number back.

Validation runs from clean clones are in `cluster_bringup/logs/repro_check/`: the
CPU paths on our laptop, and both GPU modes on the A100, where 32 of 33 numbers
landed within tolerance (the 33rd is an absolute time) and the 10 s spiking runs
gave back the published spike trains spike for spike.

## Where each number comes from

| in the paper | stage | `run_all.sh` mode |
|---|---|---|
| Table 2, single-compartment speedups | `E3_tables.sh` | `--quick` |
| Table 4, the tree threshold | `E3_tables.sh` | `--quick` |
| Fig. 3 and the abstract, speedup against run length, cost of fp64 | `E2_ksweep.sh` | `--quick` (K = 1000, 10 000), full |
| Section 2, CUDA Graphs | `E8_graphs.sh` | `--quick` (trees), full (and the spiking network) |
| Section 2, work imbalance | `E7_imbalance.sh` | full |
| Section 3(d), the 10 s run | `E5_long_run.sh` | full |
| Section 3, CPU modes on the trees | `chanmode_check.sh` | `--cpu-only` |
| Section 4 and Fig. 5, construction | `E3c_cpu.sh` | `--cpu-only` |
| Table 3, the spiking network against NEURON, CoreNEURON and Arbor | `E1_cross_simulator.sh` | `--with-simulators`; its two GENESIS CPU rows also `--cpu-only` |
| Fig. 4, GENESIS against Arbor | `E4_fp64_cost.sh` | `--with-simulators` |

Some numbers need hardware or tools a reader is unlikely to have, and their
scripts run on their own: the CPU profiles (`E6_profile.sh`, perf), the AMD
Radeon 890M under ROCm and rusticl (`E9_890m.sh`), the host's kernel-launch
cost (`host_kernel_profile.sh`, Nsight Systems), the cluster's two sockets
(`numa_check.sh`), and the code before the construction fixes
(`construction_before.sh`, which builds the upstream branch). `measure.py` lists
them under "not measured by this run".

## Your numbers will differ, and that is expected

Absolute times follow the host CPU, the card model and how warm the card is. The
tolerances in `claims.csv` allow for that, and what should reproduce is the shape
of each result: which arm wins, and by roughly how much. Three things move
results enough to know about, all found while producing the paper:

**A GPU shared with another job.** A foreign process on the card once raised
every GPU figure by about 30% while leaving the CPU arm untouched, and the
speedup curve stayed smooth and plausible. The stages wait for an idle card and
refuse a busy one.

**A cold card.** The first run after the GPU has been idle is 1.2 to 1.8 times
slower than a warm one. Each arm's first run is discarded for this reason.

**A binary built for another card.** With no device code for the card the
kernels do not launch; with only PTX they are compiled at start-up and run
slowly while still being timed as GPU runs. The stages refuse a binary without
code for the card; rebuild with `ARCH=sm_XX` (`cluster_bringup/10_build.sh`).

The spiking network runs slower on the GPU than on the CPU (Table 3). A
zero-delay network exchanges spikes every step, so every step is a dispatch.
Reproducing that is the expected outcome.

## If a number lands outside tolerance

Check `nvidia-smi` for other jobs and the machine's load, run again, and compare
ratios, not seconds. If the ordering itself inverts (the CPU beating the
GPU at large N, say), please report it to karol@chlasta.pl.

## Layout

| path | what it is |
|---|---|
| `run_all.sh` | the entry point |
| `measure.py` | the paper's numbers from a reader's run, with verdicts |
| `claims.csv` | every published number: its data file, extractor, stage, hardware and tolerance |
| `claims_extract.py` | the extractors, shared by `make_numbers.py` and `measure.py` |
| `make_numbers.py` | computes every published value from the data into `published.csv`, `paper/numbers.tex` and the README |
| `published.csv` | the published values |
| `lint_numbers.py`, `lint_allow.txt` | finds numbers typed into the manuscript instead of printed by `\claim{}` |
| `check_paths.sh` | refuses machine-specific paths outside `cluster_bringup/env.sh` |
| `tests/` | breaks the claim map, the harness and `measure.py` on purpose and checks that each refuses |
| `legacy/` | the reproduction pack of the paper's first version (August 2026), kept for the record |
| `results/` | written by a run: the stages' CSVs and logs, `ap_check.txt` |

Paths to toolkits, the comparison simulators and the ModelDB model are variables
in `cluster_bringup/env.sh`. How the NEURON, CoreNEURON and Arbor models were
matched to the GENESIS one, and checked, is in `cluster_bringup/coreneuron/README.md`
and `cluster_bringup/arbor_vanet2/README.md`.
