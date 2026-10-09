#!/bin/sh
# Is the spread of single-threaded CPU arms a NUMA placement effect?
#
#     sh cluster_bringup/campaign/numa_check.sh [reps]
#
# Night 1 of the campaign (2026-10-03) showed inf02's CPU arms bimodal, two
# clusters about 20% apart (E2 cpu_k5000: 113-116 s or 137 s), while inf03's
# were tight. A two-socket machine runs a process on either socket, and a run
# whose memory sits on the other socket is slower. This runs the same CPU arm
# (dendritic trees, N = 10 000 x 16, K = 1000) REPS times unpinned and REPS times
# pinned to socket 0 (numactl --cpunodebind=0 --membind=0), interleaved, and
# records wall time and the CPU and NUMA node each run sat on.
#
# MODES chooses the arms: the default "unpinned pinned0" as above, or "all"
# for one arm pinned to each NUMA node in turn (pinned0, pinned1, ...), which
# compares the sockets directly. BIN_ROOT runs the CPU binary of another
# checkout (a release built by prepare_node.sh) with this script.
#
# Writes logs/campaign_prep/numa_check_<node>_<time>.csv. Needs the CPU binary
# (prepare_node.sh) and numactl.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 2
REPS=${1:-6}
BIN_ROOT=$(cd "${BIN_ROOT:-$GENESIS_ROOT}" && pwd)
MODES=${MODES:-unpinned pinned0}
[ "$MODES" = all ] && MODES=$(numactl --hardware | sed -n 's/^node \([0-9]*\) cpus:.*/pinned\1/p' | tr '\n' ' ')
command -v numactl >/dev/null || { echo "no numactl on $(hostname -s)" >&2; exit 2; }
OUT=cluster_bringup/logs/campaign_prep/numa_check_$(hostname -s)_$(date +%Y%m%d_%H%M%S).csv
mkdir -p "$(dirname "$OUT")"
{
    echo "# node: $(hostname -s)"
    echo "# cpu: $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
    echo "# commit: $(git rev-parse HEAD) ($(git describe --tags --always))"
    echo "# binary: $(cd "$BIN_ROOT" && git describe --tags --always) nxgenesis_nocl sha256 $(sha256sum "$BIN_ROOT/genesis/src/nxgenesis_nocl" | cut -d' ' -f1)"
    echo "# modes: $MODES"
    numactl --hardware | sed 's/^/# /'
    echo "mode,rep,wall_s,cpu,numa_node"
} > "$OUT"

S=genesis/Scripts/benchmark/hh_multicompartment_createmap.g
one() {   # $1 mode, $2 rep
    case "$1" in
        unpinned) P="" ;;
        pinned*)  P="numactl --cpunodebind=${1#pinned} --membind=${1#pinned}" ;;
    esac
    t0=$(date +%s%N)
    env GENESIS_BENCH_CHANMODE=1 GENESIS_BENCH_NCOMP=16 $P \
        "$BIN_ROOT/genesis/src/nxgenesis_nocl" -nosimrc -notty -batch "$S" 10000 1000 </dev/null >/dev/null 2>&1 &
    pid=$!
    sleep 5   # sample placement once the run is under way
    cpu=$(ps -o psr= -p "$pid" 2>/dev/null | tr -d ' ')
    node=$(numactl --hardware | awk -v c="$cpu" '/cpus:/ { for (i = 4; i <= NF; i++) if ($i == c) print $2 }')
    wait "$pid"
    t1=$(date +%s%N)
    echo "$1,$2,$(awk "BEGIN{printf \"%.3f\", ($t1-$t0)/1e9}"),$cpu,$node" | tee -a "$OUT"
}
r=1
while [ "$r" -le "$REPS" ]; do
    for m in $MODES; do one "$m" "$r"; done
    r=$((r + 1))
done
echo "written: $OUT"
