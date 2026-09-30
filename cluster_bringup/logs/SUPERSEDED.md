# Superseded data

The files below stay in the repository so that the history of every published number can
be followed, but no number in the paper may come from them: `reproduce/make_numbers.py`
refuses any claim that names one. Each is listed with why it was replaced and by what.

Three things retired most of them:

- **Timing definition (August 2026).** Early runs timed the GPU arm with `clock_gettime`
  around the kernel and the CPU arm with GENESIS's step-loop timer, which leaves host work,
  transfers and construction out of the GPU side only. That inflates the ratio about
  tenfold. Everything from 2026-08-15 on times both arms the same way.
- **A shared card.** The first A100 end-to-end sweep ran while another user's job held the
  GPU; its GPU column is inflated about 30%, and its N=50000 block never ran.
- **Harness corrections.** The Arbor and GENESIS arms of the multi-compartment comparison
  were re-measured after the voltage cross-check found three errors in the harness.

| File | Why it was replaced | Replaced by |
|---|---|---|
| `cluster_bringup/logs/bench_inf03_NVIDIA_A100-PCIE-40GB_2026-07-23.csv` | bring-up benchmark, old timing definition | `cluster_bringup/logs/singlecomp_walltime_inf03_20260815_135147.csv` |
| `cluster_bringup/logs/gpu_sweep_a100_vs_a40_2026-07-23.txt` | bring-up comparison of the cards, old timing definition | `cluster_bringup/logs/singlecomp_walltime_inf02_20260815_132840.csv`, `..._inf03_20260815_135147.csv` |
| `cluster_bringup/logs/multicompartment_speedup_inf03_2026-07-23.txt` | before the tree-elimination kernel was validated | `cluster_bringup/logs/weekend_campaign_inf03_A100_20260816_clean.csv` |
| `cluster_bringup/logs/campaign_inf02_NVIDIA_A40_2026-07-24.csv` | single-compartment campaign, old timing definition | `cluster_bringup/logs/singlecomp_walltime_inf02_20260815_132840.csv` |
| `cluster_bringup/logs/campaign_inf03_NVIDIA_A100-PCIE-40GB_2026-07-24.csv` | as above | `cluster_bringup/logs/singlecomp_walltime_inf03_20260815_135147.csv` |
| `cluster_bringup/logs/cuda_singlecomp_campaign_inf02_A40_20260727_024553.csv` | internal timer (`t_total`), not wall clock | `cluster_bringup/logs/singlecomp_walltime_inf02_20260815_132840.csv` |
| `cluster_bringup/logs/cuda_singlecomp_campaign_inf03_A100_20260727_024613.csv` | as above | `cluster_bringup/logs/singlecomp_walltime_inf03_20260815_135147.csv` |
| `cluster_bringup/logs/cuda_singlecomp_campaign_wiq_RTX4090_20260727_210047.csv` | as above; rented card, not in the paper | none |
| `cluster_bringup/logs/multicompartment_sweep_inf02_A40_20260725_150303.csv` | step-phase sweep before the solver and construction fixes | `cluster_bringup/logs/weekend_campaign_inf02_A40_20260816_clean.csv` |
| `cluster_bringup/logs/multicompartment_sweep_inf03_A100_20260725_150506.csv` | as above | `cluster_bringup/logs/weekend_campaign_inf03_A100_20260816_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_inf02_A40_20260725_212053.csv` | July step-phase campaign; card occupancy not recorded | `cluster_bringup/logs/weekend_campaign_inf02_A40_20260816_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_inf03_A100_20260725_212113.csv` | as above | `cluster_bringup/logs/weekend_campaign_inf03_A100_20260816_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_local_AMD890M_20260725.csv` | before the correctness fixes of v2.5.1 | none yet; the revision re-measures the Radeon 890M |
| `cluster_bringup/logs/weekend_campaign_wiq_RTX4090_20260727_194140.csv` | rented card, before the correctness fixes; not in the paper | none |
| `cluster_bringup/logs/multicomp_walltime_hh_multicompartment_createmap_inf02_20260815_223158.csv` | first end-to-end sweep; re-run on an idle card together with the A100 one | `cluster_bringup/logs/multicomp_walltime_createmap_inf02_A40_clean.csv` |
| `cluster_bringup/logs/multicomp_walltime_hh_multicompartment_createmap_inf03_20260815_223158.csv` | GPU column inflated ~30% by a foreign job; N=50000 GPU replicates never ran (1.8 ms each) | `cluster_bringup/logs/multicomp_walltime_createmap_inf03_A100_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_inf02_A40_20260725_200349.csv` | an earlier July step-phase run of the same evening, before the fixes | `cluster_bringup/logs/weekend_campaign_inf02_A40_20260816_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_inf02_A40_20260725_204512.csv` | as above | as above |
| `cluster_bringup/logs/weekend_campaign_inf03_A100_20260725_200422.csv` | as above | `cluster_bringup/logs/weekend_campaign_inf03_A100_20260816_clean.csv` |
| `cluster_bringup/logs/weekend_campaign_inf03_A100_20260725_204532.csv` | as above | as above |
| `cluster_bringup/logs/multicomp_walltime_inf02_20260815_141608.csv` | first end-to-end sweep, built with the per-neuron script rather than createmap | `cluster_bringup/logs/multicomp_walltime_createmap_inf02_A40_clean.csv` |
| `cluster_bringup/logs/multicomp_walltime_inf03_20260815_141608.csv` | as above | `cluster_bringup/logs/multicomp_walltime_createmap_inf03_A100_clean.csv` |
| `cluster_bringup/logs/multicomp_walltime_createmap_refill_inf03_20260816_000911.csv` | the N=50000 block re-run into the contaminated sweep; the whole sweep was then repeated on an idle card | `cluster_bringup/logs/multicomp_walltime_createmap_inf03_A100_clean.csv` |
| `cluster_bringup/logs/crossover_inf03_20260817.csv` | before the three harness corrections found by the voltage cross-check | `cluster_bringup/logs/crossover_inf03_20260818_232057.csv` |
| `experiments/data/campaign_wallclock_raw.csv` | release v2.5 campaign, old timing definition | the cluster logs above |
| `experiments/data/campaign_wallclock_summary.csv` | as above | as above |
| `experiments/data/campaign_final_table.csv` | as above | as above |
| `experiments/data/campaign_ksweep.csv` | as above | `cluster_bringup/logs/multicomp_ksweep_inf02_A40_20260816.csv` |
| `experiments/data/campaign_warm_dispatch.csv` | as above | none |
| `paper/data/genesis25_cpu_gpu_extreme_5rep.csv` | release v2.5 manuscript, old timing definition | the cluster logs above |
| `paper/data/genesis25_cpu_gpu_extreme_5rep_speedup.csv` | as above | as above |
| `paper/data/genesis25_cpu_gpu_extreme_5rep_summary.csv` | as above | as above |
| `paper/data/genesis25_cpu_gpu_longrun_raw.csv` | as above | as above |
| `paper/data/genesis25_cpu_gpu_longrun_summary.csv` | as above | as above |
| `paper/data/genesis25_multiloop_benchmark.csv` | as above | as above |
| `paper/data/table1_runtime_summary.csv` | as above | as above |
| `paper/data/cal7difshell_nxgenesis_benchmark.csv` | release v2.5 manuscript; model not in the revised paper | none |
| `paper/data/cal8_nxgenesis_benchmark.csv` | as above | none |

## Not superseded, but incomplete

These are the only raw data behind some published numbers and are kept as they are:

- `cluster_bringup/logs/provenance_2026-08/rep_core_{1,2,3}.log`, `rep_plain_{1,2,3}.log`:
  the CoreNEURON and NEURON CPU runs of Table 5. They record the simulators' internal run
  time (74.5–75.1 s, 93.9–94.3 s) and spike count, not the wall times the paper reports.
- `cluster_bringup/logs/cn_gpu_r{1,2,3}.log`: the CoreNEURON GPU runs; solver time only.
- `cluster_bringup/logs/opencl_cluster_20260818.csv`: per-configuration means of three
  replicates; the replicates themselves were not saved.

The revision's measurement campaign re-measures all of these with every replicate logged.
