#!/bin/sh
# The "before" curve of the construction figure, on the node of the "after" one.
#
#     sh cluster_bringup/campaign/construction_before.sh <before checkout>
#
# E3c times model construction on the release (hh_branching_multicompartment_
# benchmark.g, 17 compartments per neuron, 20 steps, the whole process timed,
# bound to NUMA node 0). The release no longer contains the code from before
# the construction fixes, so until now the "before" curve came from a laptop
# in August. This builds the upstream branch at the commit before those fixes
# (<before checkout>, e.g. 5407cc2: GENESIS 2.4 with the hsolve fixes and the
# construction tests, and none of the construction fixes) with the same
# compiler, and times the same model script, taken from this checkout, the same
# way as E3c. The before code grows faster than quadratically, so the sizes
# stop where one run still takes minutes (SIZES, default 1000 ... 16 000).
#
# Writes logs/campaign_prep/construction_before_<node>_<time>/: data.csv in the
# format of experiments/data/construction_scaling_before_after.csv (rep,
# n_neurons, ncompts, total_wallclock_s, variant), every run's log, the build
# log and run.txt. Needs GCC, make, flex, bison, ncurses, numactl.
set -u
[ $# -eq 1 ] || { echo "usage: $0 <before checkout>" >&2; exit 2; }
B=$(cd "$1" && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
SIZES=${SIZES:-1000 2000 4000 8000 16000}
REPS=${REPS:-3}
NUMA=${CAMPAIGN_NUMA:-0}
G=$GENESIS_ROOT/genesis/Scripts/benchmark/hh_branching_multicompartment_benchmark.g
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/construction_before_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"

STUB=$B/locallib/libfl.a
if [ ! -f "$STUB" ]; then
    mkdir -p "$B/locallib"
    printf 'int yywrap(void){return 1;}\n' > "$B/locallib/yywrap.c"
    gcc -c "$B/locallib/yywrap.c" -o "$B/locallib/yywrap.o" && ar rcs "$STUB" "$B/locallib/yywrap.o"
fi
( cd "$B/genesis/src" && ./configure && make clean && \
  make CC="gcc -std=gnu89" TERMCAP="-lncurses -ltinfo" LEXLIB="$STUB" nxgenesis ) > "$OUT/build.log" 2>&1 \
    || { echo "build failed, see $OUT/build.log" >&2; exit 2; }
BIN=$B/genesis/src/nxgenesis
gzip -9 "$OUT/build.log"

{
echo "# node $(hostname -s), $(lscpu | sed -n 's/^Model name: *//p' | head -1)"
echo "# before: $(git -C "$B" describe --tags --always --dirty) $(git -C "$B" rev-parse HEAD)"
echo "# binary sha256 $(sha256sum "$BIN" | cut -d' ' -f1), $(gcc --version | head -1)"
echo "# model script $(git -C "$GENESIS_ROOT" describe --tags --always) genesis/Scripts/benchmark/hh_branching_multicompartment_benchmark.g sha256 $(sha256sum "$G" | cut -d' ' -f1)"
echo "# GENESIS_BENCH_CHANMODE=1, 20 steps, 4 branches of 4, numactl node $NUMA, wall clock around the process"
echo "# sizes: $SIZES; replicates: $REPS"
} > "$OUT/run.txt"
echo "rep,n_neurons,ncompts,total_wallclock_s,variant" > "$OUT/data.csv"

W=$RUN_DIR/construction_before; rm -rf "$W"; mkdir -p "$W"
cd "$W" || exit 2
for r in $(seq 1 "$REPS"); do
    for n in $SIZES; do
        log=$OUT/n${n}_r$r.log
        t0=$(date +%s%N)
        numactl --cpunodebind="$NUMA" --membind="$NUMA" env GENESIS_BENCH_CHANMODE=1 \
            timeout 7200 "$BIN" -nosimrc -notty -batch "$G" "$n" 20 4 4 > "$log" 2>&1 < /dev/null
        rc=$?
        t1=$(date +%s%N)
        wall=$(awk "BEGIN{printf \"%.3f\", ($t1 - $t0) / 1e9}")
        d=$(grep -m1 "^=== done: N=" "$log")
        built=$(echo "$d" | sed -n 's/^=== done: N= *\([0-9]*\).*/\1/p')
        if [ "$rc" = 0 ] && [ "$built" = "$n" ]; then
            echo "$r,$n,$((n * 17)),$wall,before" >> "$OUT/data.csv"
            echo "n=$n rep $r: $wall s ($d)" >> "$OUT/run.txt"
        else
            echo "n=$n rep $r: REJECTED, exit $rc, done line: ${d:-none}" >> "$OUT/run.txt"
        fi
    done
done
cat "$OUT/run.txt" "$OUT/data.csv"
echo "written: $OUT"
