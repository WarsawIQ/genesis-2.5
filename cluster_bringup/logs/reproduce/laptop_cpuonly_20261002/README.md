# `run_all.sh --cpu-only --quick` on a laptop without an NVIDIA GPU

Run 2026-10-02 on Karol Chlasta's laptop (AMD Ryzen with Radeon 890M, Linux
7.0.0-111030-tuxedo, GCC 13.3.0), from a clean export of commit 773b27e. Wall time
1 min 47 s. 5/5 claims within tolerance; the verdict table is in `cpu.txt`.

| Claim | Published | Measured here |
|---|---|---|
| Action-potential check, CPU (V) | -0.0214349 | -0.0214349 |
| Construction exponent | 0.99 | 1.03 (quick: 4 sizes, 1 replicate) |
| VAnet2 as published, one core (s) | 46.9 (cluster) | 39.1 |
| VAnet2 one solver per layer (s) | 33.2 (cluster) | 26.1 |
| Ratio | 1.41 | 1.50 |

The wall times differ from the cluster's because the CPU does; the ratio and the exponent
are what should carry over, and the action potential reproduces to the digit.
