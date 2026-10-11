# Freeze gate for v2.6.1 (candidate e80c202), 2026-10-11

Base ce21b63 (GENESIS sources of v2.5.4, as for every gate of the revision).
inf02 (A40) inf02_20261011_180525 and inf03 (A100) inf03_20261011_181052: fp32
byte-identical (14 values) with CUDA, graphs off and on, and with OpenCL; fp64
within 1e-10 V of the CPU solver (5 values). The OpenCL change of 2.6.1 splits
the multiloop only on devices with host-unified memory, so on these discrete
GPUs the output is that of 2.6.0, as the gate shows.

The wrapper log of inf03 (gate-261-inf03.log) is empty: the command that
started it redirected its output a second time, to /dev/null. The gate's own
record, summary.txt and the check logs in its directory, is complete;
gate-261-inf02.log is inf02's wrapper log.
