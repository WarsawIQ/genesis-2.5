# The CPU-only path in the container, run on the laptop, 2026-10-03

`docker build -t genesis25-cpu . && docker run --rm genesis25-cpu` on the machine the
890M results come from (image and host named in run.log). 70 s end to end.

4 of 5 claims within tolerance. The one outside, `vanet2_genesis_1solver_s`
(24.4 s against the published 33.2 s, -27% at a 25% tolerance), is an absolute wall
time measured on a cluster Xeon; this laptop's Ryzen is simply faster, and the
*ratio* of the two VAnet2 builds (1.52 against 1.41, +8%) is within tolerance. The
published VAnet2 wall times are among the prose values the revision campaign (E1)
re-measures with raw data.
