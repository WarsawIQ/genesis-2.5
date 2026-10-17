# reproduce/run_all.sh on inf03 (A100), 17 October 2026

`sh cluster_bringup/repro_check.sh` from a clean clone of `revision` at 0294cd5
(GitHub at db42007 plus the commits after it, brought as a git bundle), on an
idle NVIDIA A100-PCIE-40GB, driver 595.71.05. `header.txt` has the times:

- `--quick`: 824 s (14 min), the CUDA and OpenCL builds included. 14 numbers
  measured, all within tolerance (`run_all_quick.out`): the end-to-end maximum
  23.7x against 24.0x, Table 2 within 5% in every column, the construction
  exponent 1.03.
- full, with the quick run's binaries: 3967 s (66 min). 33 numbers measured, 32
  within tolerance and one for information (`run_all_full.out`): 1.7 million
  compartments build in 94.8 s against 94.9 s.

The 10 s spiking runs of E5 (CPU, fp32, fp64, one solver per cell, four other
seeds) gave back the campaign's spike trains spike for spike: every file is
identical, after decompression, to the campaign's of 10 October
(`E5_SPIKES_SHA256.txt`). Those files (32 MB) are not committed for that reason.
