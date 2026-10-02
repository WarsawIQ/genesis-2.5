#!/bin/sh
# The claims that need no GPU: the Hines-solver fixes, linear model
# construction, and the Vogels-Abbott network on one CPU core.
#
#     sh reproduce/stages/05_cpu.sh <results dir> [quick|full]
#
# 1. Hines fixes. hh1952_ap_verify.g builds several neurons under one hsolve,
#    each driven by `inject`, and checks that every neuron produces the same
#    action potential (NEURONS_AGREE). Before the fixes only the first neuron
#    received the injected current, so this is the defect's own test.
# 2. Construction. hh_branching_multicompartment_benchmark.g with 4 branches of 4
#    compartments (17 per neuron), timed around the whole process, at growing N;
#    the exponent of a power-law fit is the claim (0.99 after the fixes, 2.31
#    before). The published data were measured on a laptop and the script that
#    drove them was not kept; these parameters reproduce its 17 000 compartments
#    at N = 1000 and are stated here so the measurement can be repeated.
# 3. VAnet2 as published, and built as one solver per layer, on one CPU core.
set -u
RESULTS=$1
MODE=${2:-quick}
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
ROOT=$GENESIS_ROOT
cd "$ROOT" || exit 1
[ -f "$RESULTS/summary.csv" ] || echo "claim,measured,units" > "$RESULTS/summary.csv"
BIN=./genesis/src/nxgenesis_nocl
BENCH=genesis/Scripts/benchmark
[ -x "$BIN" ] || { echo "no $BIN; run cluster_bringup/12_build_cpu.sh" >&2; exit 1; }

# ------------------------------------------------------------- 1. Hines fixes
out=$($BIN -nosimrc -notty -batch $BENCH/hh1952_ap_verify.g 8 200 </dev/null 2>&1)
agree=$(echo "$out" | sed -n 's/^NEURONS_AGREE: *//p' | head -1)
vm=$(echo "$out" | sed -n 's/^RESULT_VM= *//p' | head -1)
echo "Hines fixes: 8 neurons under one hsolve, all injected: NEURONS_AGREE $agree"
case "$agree" in
    YES*) ;;
    *) echo "FAIL: the injected neurons do not agree -- the Hines-solver fixes are not in effect" >&2
       exit 1 ;;
esac
echo "cpu_ap_vm,$vm,V" >> "$RESULTS/summary.csv"

# ----------------------------------------------------------- 2. construction
CSV="$RESULTS/construction_scaling.csv"
echo "rep,n_neurons,ncompts,total_wallclock_s,variant" > "$CSV"
if [ "$MODE" = quick ]; then NLIST="1000 2000 4000 8000"; REPS=1
else                          NLIST="1000 2000 4000 8000 16000 31000"; REPS=3; fi
for r in $(seq 1 $REPS); do
    for N in $NLIST; do
        t0=$(date +%s%N)
        env GENESIS_BENCH_CHANMODE=1 $BIN -nosimrc -notty -batch \
            $BENCH/hh_branching_multicompartment_benchmark.g "$N" 20 4 4 </dev/null >/dev/null 2>&1
        t1=$(date +%s%N)
        echo "$r,$N,$((N * 17)),$(awk "BEGIN{printf \"%.3f\", ($t1-$t0)/1e9}"),after" >> "$CSV"
    done
done
python3 - "$CSV" "$RESULTS/summary.csv" <<'EOF'
import csv, math, sys
rows = list(csv.DictReader(open(sys.argv[1])))
xs = [math.log(float(r["ncompts"])) for r in rows]
ys = [math.log(float(r["total_wallclock_s"])) for r in rows]
n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
print("construction: wall time ~ compartments^%.2f over %d runs" % (b, n))
with open(sys.argv[2], "a") as f:
    f.write("construction_exponent_after,%.3f,exponent\n" % b)
    big = [float(r["total_wallclock_s"]) for r in rows if r["n_neurons"] == "31000"]
    if big:
        f.write("construction_527k_s,%.2f,s\n" % (sum(big) / len(big)))
EOF

# ---------------------------------------------------------------- 3. VAnet2
VA="$RESULTS/vanet2_cpu"
rm -rf "$VA"; mkdir -p "$VA"
cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$VA"/
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
    "$ROOT" "$ROOT" "$ROOT" "$VA" "$ROOT" > "$VA/.simrc"
REPS=1; [ "$MODE" = full ] && REPS=3
VCSV="$RESULTS/vanet2_cpu.csv"
echo "script,rep,wall_s" > "$VCSV"
for s in VAnet2-batch.g VAnet2-batch-1solver.g; do
    for r in $(seq 1 $REPS); do
        t0=$(date +%s%N)
        ( cd "$VA" && timeout 3600 "$ROOT/$BIN" -notty -batch "$s" > "out_${s%.g}_$r.log" 2>&1 )
        t1=$(date +%s%N)
        echo "$s,$r,$(awk "BEGIN{printf \"%.2f\", ($t1-$t0)/1e9}")" >> "$VCSV"
    done
done
awk -F, 'NR>1 {s[$1]+=$3; n[$1]++} END {
    a = s["VAnet2-batch.g"]/n["VAnet2-batch.g"]; b = s["VAnet2-batch-1solver.g"]/n["VAnet2-batch-1solver.g"]
    printf "VAnet2 on one core: as published %.1f s, one solver per layer %.1f s, ratio %.2f\n", a, b, a/b
    printf "vanet2_genesis_published_s,%.2f,s\nvanet2_genesis_1solver_s,%.2f,s\nvanet2_1solver_speedup,%.2f,x\n", a, b, a/b >> "'"$RESULTS/summary.csv"'"
}' "$VCSV"
