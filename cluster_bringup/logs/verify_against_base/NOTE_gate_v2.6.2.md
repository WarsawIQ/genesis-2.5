# Freeze gate for v2.6.2 (candidate 7c973aa), 2026-10-18

Base ce21b63 (GENESIS sources of v2.5.4, as for every gate of the revision), run
from fresh clones on each node (~/gate-262-<node>, ~/gate-base-262-<node>).
inf02 (A40) inf02_20261018_131948 and inf03 (A100) inf03_20261018_131948: fp32
byte-identical (14 values) with CUDA, graphs off and on, and with OpenCL; fp64
within 1e-10 V of the CPU solver (5 values). The changes of 2.6.2 are to the
element tree (compartment layout, hash table, readcell's *makeproto, pathname
buffers); they leave every computed value of the accelerator regression as it was
for v2.6.0 and v2.6.1.
