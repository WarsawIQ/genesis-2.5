#!/bin/sh
# Is chanmode 1 the fastest correct CPU reference for the dendritic trees?
#
#     sh cluster_bringup/campaign/chanmode_check.sh <release checkout> [reps]
#
# The campaign's CPU arm for the trees (tree_rep "cpu" in lib.sh) is the
# CPU-only binary in chanmode 1, chosen in July 2026 because chanmode 4 on the
# CPU binary then passed the state through without integrating it
# (BENCHMARK_NOTES.md). The spiking network's CPU arm uses chanmode 4. This
# runs the tree workload (hh_multicompartment_createmap.g, N = 10 000 trees of
# 16 compartments, K = 1000 steps) on the CPU binary of <release checkout> in
# chanmode 1, 3 and 4, interleaved, bound to NUMA node 0, and records the wall
# time, the step time the script reports and the two voltages it prints, so
# the modes can be compared for speed and for agreement.
#
# Writes logs/campaign_prep/chanmode_check_<node>_<time>.csv and the run logs
# next to it.
set -u
[ $# -ge 1 ] || { echo "usage: $0 <release checkout> [reps]" >&2; exit 2; }
REL=$(cd "$1" && pwd)
REPS=${2:-3}
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
NUMA=${CAMPAIGN_NUMA:-0}
MODES=${MODES:-1 3 4}
N=${N:-10000}; K=${K:-1000}
BIN=$REL/genesis/src/nxgenesis_nocl
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/chanmode_check_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
{
echo "# node $(hostname -s); binary $(cd "$REL" && git describe --tags --always) nxgenesis_nocl sha256 $(sha256sum "$BIN" | cut -d' ' -f1)"
echo "# hh_multicompartment_createmap.g N=$N x 16 compartments, K=$K, numactl node $NUMA, modes $MODES"
echo "chanmode,rep,wall_s,t_per_step_s,vm_soma,vm_far"
} > "$OUT/data.csv"
cd "$REL" || exit 2
for r in $(seq 1 "$REPS"); do
    for m in $MODES; do
        log=$OUT/cm${m}_r$r.log
        t0=$(date +%s%N)
        numactl --cpunodebind="$NUMA" --membind="$NUMA" env GENESIS_BENCH_CHANMODE="$m" GENESIS_BENCH_NCOMP=16 \
            timeout 3600 "$BIN" -nosimrc -notty -batch genesis/Scripts/benchmark/hh_multicompartment_createmap.g \
            "$N" "$K" > "$log" 2>&1 < /dev/null
        t1=$(date +%s%N)
        v() { sed -n "s/^$1[[:space:]]*//p" "$log" | head -1 | tr -d ' '; }
        echo "$m,$r,$(awk "BEGIN{printf \"%.3f\", ($t1 - $t0) / 1e9}"),$(v RESULT_T_PER_STEP=),$(v RESULT_VM_SOMA=),$(v RESULT_VM_FAR=)" \
            | tee -a "$OUT/data.csv"
    done
done
echo "written: $OUT"
