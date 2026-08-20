#!/bin/sh
# The spiking network: what this release adds to the accelerator.
#
# GENESIS gave each hsolve one spike generator, so a synaptically coupled
# network had to be built as one solver per cell. This release lifts that, and
# VAnet2-batch-1solver.g builds the same Vogels-Abbott model as one solver per
# layer. Two claims follow, and both are measured here rather than asserted:
# what that restructuring is worth on the CPU, and what the GPU then does with
# it. Both arms are wall-clocked around the whole process, as everywhere else
# in this pack.
#
# The GPU arm is not expected to win. A zero-delay network exchanges spikes
# every step, so multiloop batching does not apply and each step pays a
# dispatch; the paper reports parity, and reproducing parity is the point.
#
# VAnet2 cannot run under -nosimrc. Without the default schedule nothing is
# attached to the clocks, `step` returns immediately, and the run produces no
# output while still exiting 0 -- so each arm gets a scratch directory with its
# own .simrc, and a run that leaves no output is reported as a failure rather
# than being timed.
set -u
RESULTS=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# run_all.sh writes this header; a stage run on its own has to, or the
# first claim is read as the column names and every result reports "not run".
[ -f "$RESULTS/summary.csv" ] || echo "claim,measured,units" > "$RESULTS/summary.csv"
REPS=${REPS:-3}
SRC="$ROOT/genesis/Scripts/VAnet2"
BIN_CPU="$ROOT/genesis/src/nxgenesis_nocl"
BIN_GPU="$ROOT/genesis/src/nxgenesis"
WORK=${WORK:-$RESULTS/vanet2}
OUT="$RESULTS/spiking.csv"

[ -d "$SRC" ] || { echo "no $SRC; skipping"; exit 0; }
echo "arm,script,rep,wall_s" > "$OUT"

# mean wall time over REPS, or empty if any replicate produced no output
arm() {
    name=$1; bin=$2; script=$3
    [ -x "$bin" ] || { echo "  $name: $bin not built, skipping" >&2; return 1; }
    d="$WORK/$name"; rm -rf "$d"; mkdir -p "$d"
    cp "$SRC"/*.g "$SRC"/*.p "$d/" 2>/dev/null
    printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
        "$ROOT" "$ROOT" "$ROOT" "$d" "$ROOT" > "$d/.simrc"
    tot=0
    r=1
    while [ "$r" -le "$REPS" ]; do
        s=$(date +%s%N)
        ( cd "$d" && timeout 3600 "$bin" -notty -batch "$script" > "out_$r.log" 2>&1 )
        e=$(date +%s%N)
        w=$(awk -v a="$s" -v b="$e" 'BEGIN{printf "%.2f", (b-a)/1e9}')
        # A run that never stepped exits cleanly and takes a second or two.
        if ! grep -q "RUNID" "$d/out_$r.log" 2>/dev/null; then
            echo "  $name rep $r: no simulation ran, see $d/out_$r.log" >&2
            return 1
        fi
        echo "$name,$script,$r,$w" >> "$OUT"
        echo "  $name rep $r  ${w}s" >&2
        tot=$(awk -v t="$tot" -v w="$w" 'BEGIN{print t+w}')
        r=$((r + 1))
    done
    awk -v t="$tot" -v n="$REPS" 'BEGIN{printf "%.2f", t/n}'
}

echo "Vogels-Abbott COBAHH, 4000 cells, 5 s simulated, $REPS replicates per arm."
echo "One solver per cell (as published) against one per layer (this release):"
# arm() returns its mean on stdout, so its progress goes to stderr; merge the
# two here so a reviewer watching the run sees the replicates as they land.
exec 2>&1

t_pub=$(arm cpu_published "$BIN_CPU" VAnet2-batch.g) || t_pub=""
t_one=$(arm cpu_1solver   "$BIN_CPU" VAnet2-batch-1solver.g) || t_one=""
t_gpu=$(arm gpu_1solver   "$BIN_GPU" VAnet2-batch-1solver.g) || t_gpu=""

[ -n "$t_pub" ] && echo "vanet2_genesis,$t_pub,s" >> "$RESULTS/summary.csv"
[ -n "$t_one" ] && echo "vanet2_genesis_1solver,$t_one,s" >> "$RESULTS/summary.csv"
if [ -n "$t_pub" ] && [ -n "$t_one" ]; then
    awk -v a="$t_pub" -v b="$t_one" \
        'BEGIN{printf "vanet2_1solver_speedup,%.2f,x\n", a/b}' >> "$RESULTS/summary.csv"
    echo "one solver per layer is $(awk -v a="$t_pub" -v b="$t_one" 'BEGIN{printf "%.2f", a/b}')x faster on CPU"
fi
if [ -n "$t_one" ] && [ -n "$t_gpu" ]; then
    awk -v g="$t_gpu" -v c="$t_one" \
        'BEGIN{printf "vanet2_gpu_over_cpu,%.2f,x\n", g/c}' >> "$RESULTS/summary.csv"
    echo "the GPU arm takes $(awk -v g="$t_gpu" -v c="$t_one" 'BEGIN{printf "%.2f", g/c}')x the CPU time"
fi
echo "Per-replicate times: $OUT"
echo "Correctness of the accelerated network is checked separately, by"
echo "cluster_bringup/80_accel_regression.sh (ACCEL_VANET2_GPU=1)."
