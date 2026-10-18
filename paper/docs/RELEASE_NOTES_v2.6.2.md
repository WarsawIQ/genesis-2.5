# GENESIS 2.6.2

A maintenance release. It fixes defects of the element tree that came with GENESIS 2.5's constant-time model construction, found from GitHub Copilot's review of genesis-sim/genesis-2.4#7, which carries the same code, and it adds regression tests of the GENESIS core. The CPU, CUDA and OpenCL computations are those of 2.6.0 and 2.6.1, and the numbers of the SoftwareX paper, measured on v2.6.0, stand.

## Fixes

- **`readcell` no longer crashes on a cell whose compartments have coordinates.** The constant-time `Attach()` of 2.5 added a tail pointer, `childtail`, to the generic element layout but not to the layout compartments use, so a compartment's link to its next sibling lay on its own `x0`/`y0` coordinates. `readcell` sets them for every compartment it makes, so reading a branched cell from a `.p` file in cartesian or polar form crashed, in every release from v2.5 to v2.6.1. Compartments now carry `childtail` where every other element does.
- **`*makeproto` keeps the element tree consistent.** `readcell`'s `*makeproto` re-links child lists directly and left the new tail pointers, and the element hash table, pointing at the freed cell element; the next child created under the prototype crashed. It now recomputes the tails and re-hashes the prototype's tree.
- **Re-creating an element replaces it again.** Elements made outside `create` (`/output` and `/proto` at start-up, `readcell`'s compartments, `createmap`'s grid) were missing from the element hash table on which `Attach()` relies to find an existing sibling, so creating one of them again appended a second element of the same name where GENESIS 2.4 replaced it. Every attached element is now in the table.
- **Pathnames longer than 300 characters no longer overflow the two buffers 2.5 added** to `Attach()` and to path resolution. (GENESIS 2.4 itself stops at about 300 characters in older code.)

We know of no model in which these changed a computed number instead of crashing. See [KNOWN_ISSUES.md](https://github.com/WarsawIQ/genesis-2.5/blob/master/KNOWN_ISSUES.md).

## Tests and reproduction

- `genesis/Scripts/tests/run_tests.sh`: 30 regression tests of the GENESIS core, each printing PASS or FAIL: the element tree and its layout, `readcell` with coordinates, `*makeproto`, re-creating an element, long pathnames, backward Euler on one compartment in every solver mode (a defect of GENESIS 2.4 that 2.5 has always fixed), and `hsolve_many_cells.g` over 1, 2, 3 and 8 cells under one solver. On v2.6.1 four fail; on GENESIS 2.4, 19.
- `reproduce/run_all.sh` now re-measures the paper's own numbers with the campaign stages that measured them, in a reader's mode, and `reproduce/measure.py` computes them from the reader's data with the same code as the published values. It runs the tests above in every mode; CI and the container run them on every push.

## Verified

- On our laptop (GCC 15.2): all 30 tests pass; the action potential check prints the golden value, -0.02143485882 V; VAnet2 over 0.45 s gives the same 59 663 spikes as 2.6.1, file for file; model construction times and their growth are those of 2.6.1 (exponent 0.97 to 16 000 cells).
- Freeze gate on the A40 and the A100 against ce21b63 (the GENESIS sources of v2.5.4), from fresh clones of 7c973aa: fp32 byte-identical (14 values) with CUDA, graphs off and on, and with OpenCL; fp64 within 1e-10 V of the CPU solver (5 values), on both cards (`cluster_bringup/logs/verify_against_base/inf0[23]_20261018_131948/`, `NOTE_gate_v2.6.2.md`).

## Binaries

`genesis-v2.6.2-linux-x86_64.tar.gz` holds `nxgenesis_nocl` (CPU), `nxgenesis_ocl` (OpenCL 1.2, with its kernel source in `bin/hines/opencl/`) and `nxgenesis` (CUDA 12), built from the v2.6.2 tag on the UMCS cluster (AlmaLinux 8.10, glibc 2.28), with `startup/`. Its `README.txt` lists the libraries each needs and the GPU code the CUDA binary carries (native for sm_80, PTX for newer GPUs); `SHA256SUMS` inside and `cluster_bringup/logs/release/v2.6.2/manifest.txt` give the checksums. Unpacked on Ubuntu 24.04, the CPU binary passes all 30 tests, and it and the OpenCL binary under ROCm (fp64) print the same final voltage as v2.6.1; under rusticl the OpenCL binary runs on the GPU (`cluster_bringup/logs/release/v2.6.2/laptop_test.txt`).
