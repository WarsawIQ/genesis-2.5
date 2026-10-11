# Known issues

## OpenCL: a long single-compartment batch can reset an integrated GPU (fix planned for 2.6.1)

**What happens.** With `GENESIS_OCL_MULTILOOP=<K>` the OpenCL backend runs a
single-compartment network for all K steps in one kernel dispatch. Under Mesa
rusticl, which submits to the graphics queue, the amdgpu driver resets the GPU
when one dispatch runs longer than its lockup timeout (10 s by default). On the
AMD Radeon 890M the network of 50 000 cells over 50 000 steps triggers this in
every attempt; the display may flicker while the GPU recovers. ROCm submits to a
compute queue and completes the same run in 5.7 s.

**Evidence.** E9 on v2.6.0-rc4:
`cluster_bringup/logs/campaign_v2.6.0-rc4/E9_victor_20261011_044551*` (the
rejected `t1_rusticl_n50000` runs, and the kernel log with the ring timeouts and
resets), and the per-step run that completes:
`cluster_bringup/logs/campaign_prep/e9_rusticl_perstep_victor_20261011_045317/`.

**Until it is fixed.** Under rusticl, run long single-compartment models without
`GENESIS_OCL_MULTILOOP` (one dispatch per step; it completes, but on the 890M it
is slower than the CPU), or use ROCm.

**Why not in 2.6.0.** The batched tree dispatch already has a cap on integrated
GPUs (`GENESIS_OCL_TREE_MAX_NCOMPTS`, 20 000 compartments); the single-compartment
multiloop has none, and it cannot be split from the outside: a smaller
`GENESIS_OCL_MULTILOOP` than the run length makes the remaining steps no-ops
(`ocl_chip_update` in `genesis/src/hines/opencl/ocl_hsolve.c`). A fix changes the
GENESIS sources, which for 2.6.0 are frozen at v2.6.0-rc4, the tag every number
of the SoftwareX paper was measured on (decided 2026-10-11).

**Plan for 2.6.1.**
- Split the multiloop into dispatches of at most M steps inside
  `ocl_multiloop_dispatch`, keeping vm and the gating state on the device
  between them, so the result is byte-identical to one dispatch.
- Choose M from the device: on a device that drives a display (or under
  rusticl), keep one dispatch well under the lockup timeout; elsewhere keep
  today's single dispatch. Allow an override, as `GENESIS_OCL_TREE_MAX_NCOMPTS`
  does for trees.
- Tests: the 80_accel_regression golden must not change (fp32 byte-identical);
  E9's `t1_rusticl_n50000` arm must complete with no ring timeout in the kernel
  log.

## Table 1's GPU arms ran 10 steps fewer than the CPU arm (0.02%; fix in the benchmark for 2.6.1)

`hh_spiking_benchmark.g` does `reset`, `step 10` (a warm-up) and `step N`. A
single-compartment multiloop of K steps runs all K at the first solver call,
which is the first warm-up step, and makes every later call a no-op. E3 (Table 1)
and E9 set K = N, so their GPU arms ran N steps where the CPU arm ran N + 10. The
kernels are not at fault: with K = N + 10 the OpenCL multiloop in fp64 prints the
CPU's final voltage to every digit
(`cluster_bringup/logs/campaign_prep/multiloop_offset_victor_20261011_142935.csv`,
`cluster_bringup/campaign/multiloop_offset_check.sh`). With N = 50 000 the CPU did
0.02% more work, which moves no Table 1 speedup at the precision printed (their
standard deviations are 1-2%). The dendritic-tree arms set K + 10 and are not
affected. The script's comment, which attributes the different final voltages
to fp32, is wrong.

**Plan for 2.6.1.** E3 and E9 set K = N + 10 as `tree_rep` does, and the
benchmark's comment says why the final voltage depends on K.
