#!/bin/bash
# Re-measure the one createmap sweep point that failed on the A100.
#
# In multicomp_walltime_hh_multicompartment_createmap_inf03_20260815_223158.csv
# all ten N=50000 GPU replicates recorded ~1.8 ms, i.e. the binary never ran.
# It was not out of memory: re-running the same configuration by hand completes
# normally with the full 40 GB free, so the failure was transient (the card was
# in use at sweep time). This fills the gap with a fresh 10-replicate block in
# the same format so it can be concatenated onto the sweep.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
R="$GENESIS_ROOT"
cd "$R" || exit 1
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

NODE=$(hostname)
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
OUT="$R/cluster_bringup/logs/multicomp_walltime_createmap_refill_${NODE}_$(date +%Y%m%d_%H%M%S).csv"
BIN_GPU="$R/genesis/src/nxgenesis"
SCRIPT="genesis/Scripts/benchmark/hh_multicompartment_createmap.g"
N=50000
STEPS=200

# Refuse to measure on a card someone else is using -- that is what produced
# the bad block in the first place.
USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
if [ "$USED" -gt 500 ]; then
    echo "ABORT: $USED MiB already allocated on $GPU; not a clean measurement" >&2
    exit 1
fi

echo "node,gpu,ncomp_per_neuron,n_neurons,total_comps,n_steps,mode,rep,wall_s" > "$OUT"
r=1
while [ "$r" -le 10 ]; do
    S=$(date +%s%N)
    env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 \
        GENESIS_CUDA_MULTILOOP=$((STEPS + 10)) \
        timeout 1800 "$BIN_GPU" -nosimrc -notty -batch "$SCRIPT" "$N" "$STEPS" \
        >/dev/null 2>&1
    RC=$?
    E=$(date +%s%N)
    W=$(awk "BEGIN{printf \"%.6f\", ($E-$S)/1e9}")
    [ "$RC" -eq 0 ] || echo "  WARNING rep $r exited $RC" >&2
    echo "$NODE,$GPU,16,$N,$((N * 16)),$STEPS,gpu,$r,$W" >> "$OUT"
    r=$((r + 1))
done
echo "== $OUT =="
awk -F, 'NR>1{s+=$9; ss+=$9*$9; n++} END{m=s/n; printf "gpu mean=%.2f s sd=%.2f (n=%d)\n", m, sqrt(ss/n-m*m), n}' "$OUT"
