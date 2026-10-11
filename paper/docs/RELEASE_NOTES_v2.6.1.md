# GENESIS 2.6.1

A maintenance release that fixes the two known issues of 2.6.0. The CPU and CUDA code paths are those of 2.6.0, and the numbers of the SoftwareX paper, measured on v2.6.0-rc4, stand.

## Fixes

- **OpenCL on integrated GPUs: no more GPU resets from a long single-compartment run.** With `GENESIS_OCL_MULTILOOP` the OpenCL backend ran a single-compartment network for the whole run in one kernel dispatch. Under Mesa rusticl, which submits to the graphics queue, a long dispatch outlasted the driver's lockup timeout and the GPU was reset (on the Radeon 890M, 50 000 cells over 50 000 steps did so in every attempt). On a device with host-unified memory the run now goes in dispatches of about `GENESIS_OCL_DISPATCH_MS` milliseconds each (default 500), sized from the time of the one before. The state stays on the device between them and the kernel keeps no other state from one step to the next, so the result is bit for bit that of one dispatch. A discrete GPU keeps the single dispatch and the same output unless the variable is set; `GENESIS_OCL_DISPATCH_MS=0` never splits.
- **Benchmark harness: Table 1's GPU arms run the CPU's steps.** `hh_spiking_benchmark.g` steps 10 times as a warm-up before the K timed steps, and a multiloop runs all its steps at the first solver call, so with `GENESIS_*_MULTILOOP = K` the GPU ran 10 steps fewer than the CPU (0.02% of Table 1's work). The campaign (E3, E9) now sets K + 10, and the benchmark's comment, which had blamed fp32 for the different final voltages, says why they differ.

## Verified

- `cluster_bringup/campaign/ocl_chunk_check.sh` on the Radeon 890M: with 50 000 cells over 2000 steps, ROCm in fp64 prints the CPU's final voltage to every digit in 1, 5 and 1962 dispatches; fp32 under ROCm and under rusticl is the same in every split; rusticl's refused fp64 computes on the CPU, equal too. The case that was reset, 50 000 cells over 50 000 steps under rusticl, completes in 46 dispatches with no ring timeout in the kernel log.
- [freeze gate on the A40 and A100]
- [E9 on the Radeon 890M]

## Binaries

[tarball]
