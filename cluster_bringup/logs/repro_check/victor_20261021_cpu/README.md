# reproduce/run_all.sh, CPU-only paths with E1's two GENESIS CPU arms, on victor (laptop), 21 October 2026

Run from the `revision` worktree at 5664282 with the changes of 082b314 (E1_ARMS,
reproduce/codeocean_run.sh) not yet committed (GCC 15.2, Python 3.13):

- `run_all_cpu-only_quick.out`: `sh reproduce/run_all.sh --cpu-only --quick`,
  3 min with the build (E1: 130 s). Six numbers measured, none outside tolerance;
  `e1_g_cpu_pub_rel` is 1.61 here against 1.36 on inf03 (same shape: the ratio
  depends on the CPU). Its results are in `results_cpu_quick/`.
- `run_all_cpu-only_codeocean_run.out`: `SKIP_BUILD=1 sh reproduce/codeocean_run.sh`
  (the full CPU-only path, as the Code Ocean capsule runs it), 13 min. Seven numbers,
  none outside tolerance; `e1_g_cpu_pub_rel` 1.51. Its results are in
  `results_cpu_full/`.

The `runs/` directories (working copies of the model scripts) are left out, as in
`../victor_20261017_cpu/`.
