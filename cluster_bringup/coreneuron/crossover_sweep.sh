#!/bin/bash
# The GENESIS/Arbor crossover, swept rather than inferred.
#
# Two points (K=5000, K=50000) show the order reversing, and both simulators
# look linear in K, which puts the crossing at K ~ 6600. A sweep turns that from
# an extrapolation between two measurements into a curve, and shows the reader
# where each simulator wins instead of asking them to trust a fit.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
sh "$GENESIS_ROOT/cluster_bringup/coreneuron/arbor_check.sh" || exit 1
N=${N:-10000}
REPS=${REPS:-3}
KLIST=${KLIST:-"1000 2500 5000 10000 20000 50000"}
OUT="$GENESIS_ROOT/cluster_bringup/logs/crossover_$(hostname)_$(date +%Y%m%d_%H%M%S).csv"

export GENESIS_OCL_TREE_MAX_NCOMPTS=0
GEN_LD="$CUDA_HOME/lib64"
ARB_P="$ARBOR_PY"
PY="$ARBOR_PYTHON"

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
[ "$USED" -gt 500 ] && { echo "ABORT: $USED MiB already on the card" >&2; exit 1; }

# The card is read, not assumed: this sweep now runs on both nodes, and a run
# labelled with the wrong card would be worse than no run at all.
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
case "$GPU" in
    *A100*) GPU=A100 ;;
    *A40*)  GPU=A40 ;;
    *) echo "ABORT: unrecognised card '$GPU'" >&2; exit 1 ;;
esac

# A binary carrying no SASS for this card would either fail to launch or fall
# back to the CPU while still being timed as "GPU". Checked, not trusted.
CUOBJ="$CUDA_HOME/bin/cuobjdump"
CC_SM=sm_$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '. ')
if [ -x "$CUOBJ" ]; then
    "$CUOBJ" --list-elf "$GENESIS_ROOT/genesis/src/nxgenesis" 2>/dev/null \
        | grep -q "$CC_SM" || {
        echo "ABORT: nxgenesis has no $CC_SM code for this $GPU" >&2; exit 1; }
fi
echo "== card $GPU, binary carries $CC_SM =="

echo "simulator,node,gpu,n_neurons,ncomp,n_steps,rep,wall_s" > "$OUT"
echo "== crossover sweep, N=$N on $(hostname) =="

for K in $KLIST; do
    cd "$GENESIS_ROOT" || exit 1
    for r in $(seq 1 "$REPS"); do
        S1=$(date +%s%N)
        LD_LIBRARY_PATH="$GEN_LD" env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 \
            GENESIS_CUDA_MULTILOOP=$((K + 10)) timeout 3600 \
            ./genesis/src/nxgenesis -nosimrc -notty -batch \
            genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$N" "$K" >/dev/null 2>&1
        E1=$(date +%s%N)
        echo "GENESIS 2.5,$(hostname),$GPU,$N,16,$K,$r,$(awk "BEGIN{printf \"%.4f\", ($E1-$S1)/1e9}")" >> "$OUT"
    done

    cd "$GENESIS_ROOT/cluster_bringup/coreneuron" || exit 1
    for r in $(seq 1 "$REPS"); do
        w=$(PYTHONPATH="$ARB_P" LD_LIBRARY_PATH="$GEN_LD:$ARBOR_PREFIX/lib" \
            USE_GPU=1 timeout 3600 "$PY" hh_multicomp_arbor.py "$N" "$K" 2>&1 \
            | sed -n 's/^RESULT_WALL_S=//p')
        echo "Arbor 0.10.0,$(hostname),$GPU,$N,16,$K,$r,${w:-NA}" >> "$OUT"
    done
    echo "  K=$K done $(date +%T)"
done
echo "== $OUT =="
