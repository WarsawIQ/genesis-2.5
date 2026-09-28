#!/bin/sh
# Does the GPU arm still compute the right answer at K=5000?
#
# The K-sweep gives 57x end-to-end at N=10000, K=5000, while the step-phase
# campaign reports 13.7x at the same N. End-to-end cannot exceed step-phase --
# it contains the same simulation plus unaccelerated construction -- so either
# one figure is measured wrong or the GPU arm is skipping work. Compare the
# recorded voltages against the CPU arm before believing the speedup.
set -u
R="$HOME/genesis-2.5"
cd "$R" || exit 1
export LD_LIBRARY_PATH="/storage/opt/cuda/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}"
export GENESIS_OCL_TREE_MAX_NCOMPTS=0
S="genesis/Scripts/benchmark/hh_multicompartment_createmap.g"
N=${N:-10000}
K=${K:-5000}

echo "=== N=$N K=$K ==="
echo "--- CPU (chanmode 1, fp64) ---"
env GENESIS_BENCH_CHANMODE=1 GENESIS_BENCH_NCOMP=16 \
    timeout 1800 ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch "$S" "$N" "$K" 2>&1 \
    | grep -E "RESULT_VM|RESULT_T_PER_STEP|RESULT_T_TOTAL"

echo "--- GPU (chanmode 4, multiloop) ---"
env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 GENESIS_CUDA_MULTILOOP=$((K + 10)) \
    timeout 1800 ./genesis/src/nxgenesis -nosimrc -notty -batch "$S" "$N" "$K" 2>&1 \
    | grep -E "RESULT_VM|RESULT_T_PER_STEP|RESULT_T_TOTAL|MULTILOOP|steps profiled|per-step mode"
