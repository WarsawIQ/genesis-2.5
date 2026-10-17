# reproduce/run_all.sh, CPU-only paths, on victor (laptop), 17 October 2026

Run from a clean clone of `revision` at 231bd80 (GCC 15.2, Python 3.13):

- `run_all_cpu-only_quick.out`: `sh reproduce/run_all.sh --cpu-only --quick`,
  1 min 37 s with the build. Three numbers measured, all within tolerance.
- `run_all_cpu-only.out`: `SKIP_BUILD=1 sh reproduce/run_all.sh --cpu-only`, 9 min.
  Its results are in `results_cpu_full/`.

That run judged the absolute construction time of 1.7 million compartments
(54.4 s here, 94.9 s on inf03) against its tolerance and called it OUTSIDE. An
absolute time depends on the machine, so measure.py now prints it for
information and judges only ratios and exponents; `measure_after_fix.txt` is the
same results read by the fixed measure.py.
