# Verification of the fp64 and CUDA Graphs changes

These are the one-off driver scripts and every output of the checks run on the UMCS cluster
while the run-time fp64 option (branch `fp64-runtime`) and CUDA Graph dispatch (branch
`cuda-graphs`) were written. The same procedure now exists as one script,
`cluster_bringup/82_verify_against_base.sh`. Build logs are gzipped.

Base for every comparison: ce21b63 (before any fp64 work). Goldens were recorded from the
base on the card under test, because the committed goldens are per device and the OpenCL
one predated a later fix.

## A40 (inf02), 2026-09-30 and 2026-10-02 — `A40_20260930_20261002/`

| Script | Commit tested | What it checked | Result |
|---|---|---|---|
| `run.sh` | f16d235 | CUDA fp32 vs base; fp64 recorded | fp32 13/13 identical; VAnet2 arm empty in both (see `run2`) |
| `run2.sh` | 658fddf | after adding genesis/startup: CUDA fp32 vs base (`golden_base2.txt`), fp64, fp64 with `-fmad=false` | fp32 14/14 identical, VAnet2 md5 equal to the August golden; fp64 off by 2e-10/3.8e-10 V with and without FMA |
| (by hand) | 658fddf | CPU chanmode 1 vs 4 vs GPU fp64 chanmode 4 | the 2e-10/3.8e-10 V is chanmode 1 vs 4 on the CPU; GPU fp64 = CPU chanmode 4 to every digit |
| `run3.sh` | 44b1fc4 | OpenCL base golden; OpenCL fp32 and fp64 | fp64 5/5; fp32 failed the precision check: GPU arms printed no precision |
| (by hand) | 44b1fc4 | gdb on the OpenCL fp32 crash | heap corruption from esz = 0 in fp32, fixed in 38fba74 |
| `run4.sh` | 38fba74 | OpenCL fp32 vs base, fp64, invalid value | 14/14 identical, 5/5, refused |
| `run5.sh` | 909d47a | graphs off/on fp32, fp64 with graphs, graph probe | 14/14 and 14/14 identical, 5/5; probe in `../cuda_graph_probe_inf02_20261002_131900.csv` |

## A100 (inf03), 2026-10-02 — `A100_20261002/`

`run6.sh`: the same as above on the A100, CUDA and OpenCL, with the graph probe.
