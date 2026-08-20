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

# run_all.sh puts the CUDA runtime on the library path; a stage run on its own
# has to as well, or the GPU binary dies with "libcudart.so.12: cannot open
# shared object file" and the arm is recorded as a failure that never ran.
if [ -z "${CUDA_HOME:-}" ]; then
    CUDA_HOME=$(ls -d /usr/local/cuda* /storage/opt/cuda/cuda-* 2>/dev/null | tail -1)
fi
[ -d "${CUDA_HOME:-}/lib64" ] && \
    LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" && export LD_LIBRARY_PATH
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

# ------------------------------------------------------------ spike counts
# A speedup from a network that fires differently is not a reproduction, so
# the two arms are also compared on what they produced. These runs record
# every spike and are therefore NOT the runs timed above: spikehistory walks
# its message list on each event, which costs wall time the published figures
# do not include. Set SKIP_SPIKE_CHECK=1 to leave them out.
if [ "${SKIP_SPIKE_CHECK:-0}" != 1 ] && [ -x "$BIN_GPU" ]; then
    echo
    echo "Spike counts, CPU against GPU (recorded runs, not timed):"
    n_cpu=""; n_gpu=""
    for a in cpu gpu; do
        b=$BIN_CPU; [ "$a" = gpu ] && b=$BIN_GPU
        d="$WORK/spikes_$a"; rm -rf "$d"; mkdir -p "$d"
        cp "$SRC"/*.g "$SRC"/*.p "$d/" 2>/dev/null
        printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
            "$ROOT" "$ROOT" "$ROOT" "$d" "$ROOT" > "$d/.simrc"
        ( cd "$d" && GENESIS_VANET2_SPIKEFILE="$d/spikes.txt" \
            timeout 3600 "$b" -notty -batch VAnet2-batch-1solver.g > out.log 2>&1 )
        n=$(wc -l < "$d/spikes.txt" 2>/dev/null || echo 0)
        echo "  $a  $n spikes"
        [ "$a" = cpu ] && n_cpu=$n || n_gpu=$n
    done
    if [ "${n_cpu:-0}" -gt 0 ] && [ "${n_gpu:-0}" -gt 0 ]; then
        awk -v c="$n_cpu" -v g="$n_gpu" \
            'BEGIN{d=(g-c)/c*100; if(d<0)d=-d; printf "vanet2_spike_agreement_pct,%.2f,pct\n", d}' \
            >> "$RESULTS/summary.csv"
        awk -v c="$n_cpu" -v g="$n_gpu" \
            'BEGIN{d=(g-c)/c*100; if(d<0)d=-d; printf "the two arms differ by %.2f%% on spike count\n", d}'
    fi
fi

echo "The membrane trace itself is checked by"
echo "cluster_bringup/80_accel_regression.sh (ACCEL_VANET2_GPU=1)."
