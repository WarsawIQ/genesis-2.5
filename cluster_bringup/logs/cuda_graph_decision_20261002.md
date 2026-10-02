# CUDA Graphs: measured gain and decision (2026-10-02, A40 and A100)

Data: `cuda_graph_probe_inf02_20261002_131900.csv` (A40, commit 909d47a, 5 replicates per
arm, interleaved). Speedup = mean wall without graphs / mean wall with graphs, uncertainty
from the two arms' relative standard deviations.

| Workload | Off (s) | On (s) | Speedup | Step phase saved |
|---|---|---|---|---|
| Tree loop, N=10000×16, K=5000 | 2.151 ± 0.040 | 2.125 ± 0.016 | 1.012 ± 0.020 | 3.3% |
| Tree loop, N=10000×16, K=50000 | 8.439 ± 0.041 | 8.331 ± 0.028 | 1.013 ± 0.006 | 1.7% |
| VAnet2, one solver per layer, 100000 steps | 43.196 ± 0.996 | 43.206 ± 1.471 | 1.000 ± 0.041 | — |

Results with graphs on are unchanged: the accelerator regression is byte-identical (fp32)
and within 1e-10 V of the CPU (fp64), and all ten spiking runs produced the same spike
train.

**Decision** (rule fixed in advance in the feature specification: below 5% in both
workloads, graphs stay off by default and the measured gain is reported): graphs stay off
by default; `GENESIS_CUDA_GRAPH=1` remains available.

**What it says.** In the tree loop the host side costs a few microseconds per step against
about 65 µs of kernel time, so removing launch overhead can buy only a few percent, which
is what was measured. In the spiking network, graphs remove the launch overhead and gain
nothing: the per-step cost there is the host's spike delivery and the synchronisation it
needs, not kernel launches. Speeding that workload up needs spike delivery on the device,
not cheaper launches.

## A100 (inf03), same day

Data: `cuda_graph_probe_inf03_20261002_203248.csv` (commit 909d47a, 5 replicates per arm,
interleaved).

| Workload | Off (s) | On (s) | Speedup | Step phase saved |
|---|---|---|---|---|
| Tree loop, K=5000 | 1.789 ± 0.031 | 1.680 ± 0.003 | 1.064 ± 0.019 | 16.7% (0.612 → 0.510 s) |
| Tree loop, K=50000 | 4.646 ± 0.019 | 4.500 ± 0.017 | 1.032 ± 0.006 | 4.2% (3.445 → 3.300 s) |
| VAnet2, 100000 steps | 48.330 ± 1.351 | 47.710 ± 1.265 | 1.013 ± 0.039 | — |

Results unchanged again (regression byte-identical, fp64 within 1e-10 V, one spike train).

On the A100 the kernels are faster, so launch overhead is a larger share of a step and
graphs recover more: about 0.10–0.15 s of step phase at both run lengths, roughly half of
the 0.21 s fixed dispatch cost measured in August. The spiking network still gains nothing
beyond its scatter.

**Caveat on the spiking times.** The probe records every spike (`GENESIS_VANET2_SPIKEFILE`)
to check that graphs do not change them, and recording slows the run: these wall times
(43–48 s) are not comparable with the timing runs of the paper (about 36 s on the A100).
The off/on ratio is unaffected, since both arms record.

## Decision

Under the rule fixed in advance, the A40 result (below 5% everywhere) keeps graphs off, but
the A100 tree loop at K=5000 (6.4%) falls in the 5–10% band where the decision is Karol's.
Pending that decision, graphs stay off by default. The campaign repeats the probe on the
release tag on both cards (E8).

**Decided 2026-10-02 (Karol Chlasta): off by default.** The default path stays the one
measured longest and used for every published number; `GENESIS_CUDA_GRAPH=1` is
documented as an option with the gains above.
