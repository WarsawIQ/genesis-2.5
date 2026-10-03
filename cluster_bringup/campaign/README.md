# The revision measurement campaign

Every number in the revised paper is measured by the stages in this folder, on
one tagged commit (`v2.6.0-rc1`), and written to
`cluster_bringup/logs/campaign_v2.6.0-rc1/`. The experiments, E1 to E9, answer
the reviewers' points 3, 4, 6, 7, 8 and 9:

| Stage | What it measures | Where | Replicates |
|---|---|---|---|
| E1 | the spiking network against NEURON, CoreNEURON and Arbor, every arm in one session, interleaved, with a GENESIS fp64 GPU arm | inf03 (A100) | 5 |
| E2 | end-to-end speedup against run length, fp32 and fp64; the one maximum speedup the paper quotes | A40, A100 | 5 |
| E3 | the single-compartment and dendritic-tree tables and figures, model construction, PGENESIS on MPI | A40, A100, CPU | 10 (3 for construction and MPI) |
| E4 | what fp64 costs; the crossover with Arbor when both compute in double | A40, A100 | 3 |
| E5 | 10 s of the spiking network in fp32, fp64 and on the CPU: spike counts, rates, ISIs, first divergence | A100 | 3 |
| E6 | CPU profiles of GENESIS and CoreNEURON on both workloads | inf03 | 1 profile + 3 timed |
| E7 | work imbalance: trees of 8 and 64 compartments mixed in every warp, sorted, and uniform with the same total | A100 | 5 |
| E8 | CUDA Graphs on and off | A40, A100 | 5 |
| E9 | OpenCL on the AMD Radeon 890M under ROCm and Mesa rusticl | laptop | 3 |

## What every run does

`lib.sh` is shared by all stages. Each run:

- runs only on a clean checkout of the campaign tag (`CAMPAIGN_DRY=1` allows
  anything, writes to `logs/campaign_dry/`, and the claim map refuses those files);
- refuses a GPU that has another process on it, before and after the run, waits
  and retries (`CAMPAIGN_WAIT_S`, `CAMPAIGN_WAIT_TRIES`), then gives up for the
  night with exit code 3;
- checks the start-up banner (backend, precision, graph setting) and rejects the
  run if it does not match what the arm asked for;
- checks with `sanity.sh` that the run did its work (result lines, model size,
  run length, a plausible wall time from `bands.csv`), and rejects it otherwise;
- records a header (commit, node, CPU, governor, GPU, driver, clocks, GPU
  processes) at the top of the CSV and of the run's own log.

Each arm has one discarded warm-up run (rep 0). Replicates interleave the arms in
an order rotated by the replicate number. A session is one invocation of a stage
on one node; ratios are formed only within a session. A stopped stage resumes
its session where it stopped; a rejected run is retried once; an arm with fewer
replicates than the others is reported as incomplete and never averaged.

`report.py` writes `<stage>_<session>_report.md` next to each CSV: per arm the
valid runs, mean, SD, RSD (flagged above 5%), range and rejections, the stage's
ratios with one uncertainty definition (ratio of means, relative SDs in
quadrature), and the operator's notes from `runs/<session>/notes`.

`reproduce/tests/test_campaign.sh` checks every refusal above without a GPU.

## Model switches added for the campaign

Both default to the published behaviour when unset.

- `GENESIS_VANET2_TMAX` (both VAnet2 scripts): simulated seconds after the 0.05 s
  of driven input; 9.95 for E5's 10 s run.
- `GENESIS_BENCH_NCOMP_MIX_A`, `GENESIS_BENCH_NCOMP_MIX_B`,
  `GENESIS_BENCH_MIX_ORDER` (`hh_multicompartment_createmap.g`): half the neurons
  with A compartments and half with B, alternating (order 0) or in two blocks
  (order 1). N must be even.

## Before the tag: dry run and freeze gate

Toolchains on UMCS: `WORK_DIR=$HOME/tc-verify-20260929`, built from
`cluster_bringup/toolchains/` and verified on 2026-09-30. The Arbor catalogue
(`toolchains/45_arbor_cobahh_catalogue.sh`) is built on a GPU node.

1. Dry run on each node, from its own checkout of the candidate commit:
   `CAMPAIGN_DRY=1 sh cluster_bringup/campaign/prepare_node.sh && CAMPAIGN_DRY=1 sh cluster_bringup/campaign/run_night.sh`;
   on the laptop `CAMPAIGN_DRY=1 sh cluster_bringup/campaign/E9_890m.sh`.
   Every stage must end `complete`; the dry data go to `logs/campaign_dry/`.
2. Freeze gate on inf02 and inf03: `BASE=<checkout of ce21b63> sh cluster_bringup/82_verify_against_base.sh`
   from the candidate checkout. fp32 must be byte-identical to the base with
   CUDA (graphs off and on) and OpenCL, fp64 within 1e-10 V of the CPU
   solver (Constitution III). Outputs go to `logs/verify_against_base/`.
3. CI green on the candidate commit.
4. Then, and only on Karol's word: merge into `master`, tag `v2.6.0-rc1`,
   push the tag. From then on only documentation, analysis and packaging change.

All cluster access goes through one `ssh -fN miranda` master connection;
`sync_from_cluster.sh` refuses to run without it. No script or loop may log
in by itself.
