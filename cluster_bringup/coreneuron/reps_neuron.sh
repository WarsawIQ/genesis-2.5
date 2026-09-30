#!/bin/bash
# Three replicates of each NEURON arm of Table 5 (NEURON and CoreNEURON, CPU,
# single-threaded), so the comparison against the three-replicate GENESIS
# measurement compares like with like.
#
# Needs toolchains/fetch_modeldb_83319.sh, prepare_cobahh.sh and
# build_mechanisms.sh cpu.
#
# From as-found/reps_neuron.sh. That version printed each wall time to the
# terminal and nowhere else, which is why the 76.5 s and 95.8 s of Table 5 have
# no data file behind them. The wall times and spike counts now go to a CSV.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$COBAHH_DIR" || exit 1
PY=$(command -v "$NRN_PYTHON")
OUT="$GENESIS_ROOT/cluster_bringup/logs/neuron_arms_$(hostname)_$(date +%Y%m%d_%H%M%S).csv"
echo "node,arm,rep,wall_s,rc,spikes" > "$OUT"

echo "node=$(hostname)"
for arm in core plain; do
    echo "=== $arm ==="
    for r in 1 2 3; do
        S=$(date +%s%N)
        timeout 1700 "$PY" "run_$arm.py" > "rep_${arm}_$r.log" 2>&1
        RC=$?
        E=$(date +%s%N)
        SP=$(wc -l < out.dat 2>/dev/null)
        W=$(awk "BEGIN{printf \"%.2f\", ($E-$S)/1e9}")
        echo "  $arm rep $r wall=$W s rc=$RC spikes=$SP"
        echo "$(hostname),$arm,$r,$W,$RC,$SP" >> "$OUT"
    done
done
echo "written: $OUT"
