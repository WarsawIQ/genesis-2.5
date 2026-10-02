# CUDA Graphs: measured gain and decision (2026-10-02)

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

The A100 measurement waits for the card to be free; the campaign repeats this on the
release tag (E8).
