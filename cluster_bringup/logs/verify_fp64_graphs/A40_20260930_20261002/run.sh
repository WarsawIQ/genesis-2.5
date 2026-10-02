#!/bin/bash
# F1 check on inf02 (A40): base commit vs fp64-runtime, fp32 regression byte-identical.
set -u
T=$HOME/f1-test
echo "START $(date -Is) $(hostname) $(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader)"
cd $HOME/genesis-2.5-git && echo "base: $(git log --oneline -1)"
sh cluster_bringup/10_build.sh > $T/build_base.log 2>&1 || { echo "BASE BUILD FAILED"; tail -20 $T/build_base.log; exit 1; }
ACCEL_GOLDEN=$T/golden_base.txt sh cluster_bringup/80_accel_regression.sh record > $T/record_base.log 2>&1 || { echo "BASE RECORD FAILED"; tail -20 $T/record_base.log; exit 1; }
echo "base recorded; vs committed golden:"; diff <(grep -v "^#" cluster_bringup/accel_regression_golden.txt) <(grep -v "^#" $T/golden_base.txt) > $T/base_vs_committed.diff && echo "  identical to the committed golden" || echo "  differs from committed golden: $(wc -l < $T/base_vs_committed.diff) diff lines"
cd $HOME/genesis-2.5-f1 && echo "f1: $(git log --oneline -1)"
sh cluster_bringup/10_build.sh > $T/build_f1.log 2>&1 || { echo "F1 BUILD FAILED"; grep -n -i -E "error" $T/build_f1.log | head -20; exit 1; }
ACCEL_GOLDEN=$T/golden_base.txt sh cluster_bringup/80_accel_regression.sh check > $T/check_f1_fp32.log 2>&1; echo "F1 fp32 check rc=$?"; tail -5 $T/check_f1_fp32.log
GENESIS_GPU_PRECISION=fp64 ACCEL_GOLDEN=$T/golden_f1_fp64.txt sh cluster_bringup/80_accel_regression.sh record > $T/record_f1_fp64.log 2>&1; echo "F1 fp64 record rc=$?"
grep -h "kernels" $T/*.log | sort | uniq -c | head
echo "END $(date -Is)"
