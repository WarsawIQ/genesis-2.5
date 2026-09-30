#!/bin/bash
# Spot-check the July step-phase numbers on an idle card.
#
# The August createmap sweep was inflated ~30% on the A100 by a foreign GPU job
# while the CPU arm was untouched, and the contention was steady enough that the
# curve still looked smooth. The step-phase figures in Table 3 come from a July
# campaign whose card occupancy nobody recorded, so they need the same check.
# Three sizes are enough to tell a 30% offset from agreement.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
R="$GENESIS_ROOT"
cd "$R" || exit 1
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
# The July campaign exports this; without it the tree multiloop refuses any
# hsolve over 20000 compartments and silently falls back to per-step dispatch,
# which is a different measurement entirely.
export GENESIS_OCL_TREE_MAX_NCOMPTS=0

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
if [ "$USED" -gt 500 ]; then
    echo "ABORT: $USED MiB already allocated on $GPU" >&2
    exit 1
fi
echo "node=$(hostname) gpu=$GPU idle=${USED}MiB"

BIN_CPU="$R/genesis/src/nxgenesis_nocl"
BIN_GPU="$R/genesis/src/nxgenesis"
SCRIPT="genesis/Scripts/benchmark/hh_multicompartment_benchmark.g"

# RESULT_T_PER_STEP is the simulator's own step-phase timer, the same quantity
# the July campaign recorded.
step_time() {
    env GENESIS_BENCH_CHANMODE="$2" GENESIS_BENCH_NCOMP=16 ${3:-} \
        timeout 1800 "$1" -nosimrc -notty -batch "$SCRIPT" "$4" "$5" 2>/dev/null \
        | sed -n 's/^RESULT_T_PER_STEP= *//p' | head -1
}

for N in 10000 50000; do
    STEPS=100
    [ "$N" -lt 5000 ] && STEPS=200
    csum=0; gsum=0
    for r in 1 2 3; do
        c=$(step_time "$BIN_CPU" 1 "" "$N" "$STEPS")
        g=$(step_time "$BIN_GPU" 4 "GENESIS_CUDA_MULTILOOP=$((STEPS + 10))" "$N" "$STEPS")
        csum=$(awk "BEGIN{print $csum + $c}")
        gsum=$(awk "BEGIN{print $gsum + $g}")
    done
    awk "BEGIN{c=$csum/3; g=$gsum/3; printf \"N=%d  cpu=%.3e  gpu=%.3e  step-phase speedup=%.1fx\n\", $N, c, g, c/g}"
done
