#!/bin/bash
# Three replicates of each NEURON arm, so the head-to-head against the
# three-replicate GENESIS measurement compares like with like instead of
# resting on a single run per simulator.
export PATH="$HOME/.local/bin:$PATH"
D="$HOME/coreneuron_cmp/destexhe_benchmarks/NEURON/cobahh"
cd "$D" || exit 1
PY=$(command -v python3.12)

echo "node=$(hostname)"
for arm in core plain; do
    echo "=== $arm ==="
    for r in 1 2 3; do
        S=$(date +%s%N)
        timeout 1700 "$PY" "run_$arm.py" > "rep_${arm}_$r.log" 2>&1
        RC=$?
        E=$(date +%s%N)
        SP=$(wc -l < out.dat 2>/dev/null)
        awk "BEGIN{printf \"  $arm rep $r wall=%.2f s rc=$RC spikes=$SP\n\", ($E-$S)/1e9}"
    done
done
