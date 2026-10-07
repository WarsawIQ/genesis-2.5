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
# Writes logs/campaign_prep/numa_check_<node>_<time>.csv. Needs the CPU binary
# (prepare_node.sh) and numactl.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 2
REPS=${1:-6}
command -v numactl >/dev/null || { echo "no numactl on $(hostname -s)" >&2; exit 2; }
OUT=cluster_bringup/logs/campaign_prep/numa_check_$(hostname -s)_$(date +%Y%m%d_%H%M%S).csv
mkdir -p "$(dirname "$OUT")"
{
    echo "# node: $(hostname -s)"
    echo "# cpu: $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
    echo "# commit: $(git rev-parse HEAD) ($(git describe --tags --always))"
    numactl --hardware | sed 's/^/# /'
    echo "mode,rep,wall_s,cpu,numa_node"
} > "$OUT"

S=genesis/Scripts/benchmark/hh_multicompartment_createmap.g
one() {   # $1 mode, $2 rep
    case "$1" in
        unpinned) P="" ;;
        pinned0)  P="numactl --cpunodebind=0 --membind=0" ;;
    esac
    t0=$(date +%s%N)
    env GENESIS_BENCH_CHANMODE=1 GENESIS_BENCH_NCOMP=16 $P \
        ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch "$S" 10000 1000 </dev/null >/dev/null 2>&1 &
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
    one unpinned "$r"
    one pinned0 "$r"
    r=$((r + 1))
done
echo "written: $OUT"
