#!/bin/sh
# Wall clock against run length, which is what makes the Arbor comparison
# meaningful: the two simulators cross, so a single run length answers only
# which side of the crossing was chosen.
set -u
RESULTS=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# run_all.sh writes this header; a stage run on its own has to, or the
# first claim is read as the column names and every result reports "not run".
[ -f "$RESULTS/summary.csv" ] || echo "claim,measured,units" > "$RESULTS/summary.csv"
cd "$ROOT" || exit 1
S=genesis/Scripts/benchmark/hh_multicompartment_createmap.g
N=10000
OUT="$RESULTS/crossover.csv"
echo "simulator,n_steps,rep,wall_s" > "$OUT"

for K in 5000 50000; do
    r=1; tot=0
    while [ "$r" -le 3 ]; do
        t0=$(date +%s%N)
        env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 GENESIS_CUDA_MULTILOOP=$((K+10)) \
            ./genesis/src/nxgenesis -nosimrc -notty -batch "$S" "$N" "$K" >/dev/null 2>&1
        t1=$(date +%s%N)
        w=$(awk "BEGIN{printf \"%.4f\", ($t1-$t0)/1e9}")
        echo "GENESIS 2.5,$K,$r,$w" >> "$OUT"
        tot=$(awk "BEGIN{print $tot + $w}")
        r=$((r+1))
    done
    awk -v t="$tot" -v K="$K" 'BEGIN{printf "K=%s  GENESIS GPU %.2fs\n", K, t/3}'
    awk -v t="$tot" -v K="$K" 'BEGIN{printf "crossover_genesis_k%s,%.2f,s\n", K, t/3}' >> "$RESULTS/summary.csv"
done
# The Arbor arm, when the reviewer has one. Without it the GENESIS times above
# still stand on their own; with it the crossing itself is measurable, and the
# crossing is the claim -- neither simulator is faster in general.
ARB="$ROOT/cluster_bringup/coreneuron/hh_multicomp_arbor.py"
if [ -f "$ARB" ] && python3 -c "import arbor" 2>/dev/null; then
    for K in 5000 50000; do
        r=1; tot=0
        while [ "$r" -le 3 ]; do
            w=$(USE_GPU=1 timeout 3600 python3 "$ARB" "$N" "$K" 2>&1 \
                | sed -n 's/^RESULT_WALL_S=//p')
            [ -n "$w" ] || { echo "  Arbor K=$K rep $r failed"; break; }
            echo "Arbor 0.10.0,$K,$r,$w" >> "$OUT"
            tot=$(awk "BEGIN{print $tot + $w}")
            r=$((r+1))
        done
        [ "$r" -gt 3 ] && awk -v t="$tot" -v K="$K" \
            'BEGIN{printf "crossover_arbor_k%s,%.2f,s\n", K, t/3}' >> "$RESULTS/summary.csv"
    done

    # Two points per simulator give the intercept and slope, and the crossing
    # follows. It is keyed by card: on our A40 it falls at K ~ 1,800 and on the
    # A100 at K ~ 6,400, because our kernel is fp32 where Arbor computes in
    # double. A crossing checked against the wrong card would look like a
    # failed reproduction when nothing had gone wrong.
    card=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    key=crossover_k; case "$card" in *A40*) key=crossover_k_a40 ;; esac
    awk -F, -v key="$key" '
        $1 ~ /GENESIS/ { g[$2] += $4; gn[$2]++ }
        $1 ~ /Arbor/   { a[$2] += $4; an[$2]++ }
        END {
            if (gn[5000] && gn[50000] && an[5000] && an[50000]) {
                g1 = (g[50000]/gn[50000] - g[5000]/gn[5000]) / 45000
                a1 = (a[50000]/an[50000] - a[5000]/an[5000]) / 45000
                g0 = g[5000]/gn[5000] - g1*5000
                a0 = a[5000]/an[5000] - a1*5000
                if (g1 != a1) printf "%s,%.0f,steps\n", key, (a0-g0)/(g1-a1)
            }
        }' "$OUT" >> "$RESULTS/summary.csv"
    grep -h "^$key," "$RESULTS/summary.csv" | tail -1 \
        | awk -F, '{printf "the two GPU lines cross at K ~ %d\n", $2}'
else
    echo "Arbor arm skipped (no importable arbor); the crossing needs both sides."
    echo "See reproduce/README.md for how ours was built."
fi
