#!/bin/sh
# Validate reproduce/run_all.sh on a GPU node, as a reader would run it: --quick,
# then the full mode with the binaries the quick run built. Run on the node
# (inf03 = A100), from a clean clone of the commit under test:
#
#     sh cluster_bringup/repro_check.sh [<out dir>]
#
# Writes, under <out dir> (default cluster_bringup/logs/repro_check/<node>_<time>/):
#   header.txt                 node, commit, card, and each mode's exit code and time
#   run_all_quick.out          the --quick run's console output
#   run_all_full.out           the full run's console output
#   results_quick/, results_full/   reproduce/results/ of each run, without the
#                              scratch run directories (the spike files are large)
#   DONE                       when both have finished: the marker a waiting
#                              session watches, so nothing has to poll the node
# Then, on the machine that holds the repository:
#     CLUSTER_ROOT=<clone> sh cluster_bringup/sync_from_cluster.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST=$(uname -n); HOST=${HOST%%.*}
OUT=${1:-$ROOT/cluster_bringup/logs/repro_check/${HOST}_$(date +%Y%m%d_%H%M%S)}
mkdir -p "$OUT"
cd "$ROOT" || exit 1

keep() {   # <dest>: reproduce/results/ without its scratch runs/
    mkdir -p "$1"
    (cd reproduce/results && tar cf - --exclude=./runs .) | (cd "$1" && tar xf -)
}
{
    echo "# node: $HOST"
    echo "# commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "# started: $(date -Is)"
    command -v nvidia-smi > /dev/null 2>&1 \
        && echo "# gpu: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"
} > "$OUT/header.txt"

t0=$(date +%s)
sh reproduce/run_all.sh --quick > "$OUT/run_all_quick.out" 2>&1
echo "quick: exit $?, $(( $(date +%s) - t0 )) s" >> "$OUT/header.txt"
keep "$OUT/results_quick"

t0=$(date +%s)
SKIP_BUILD=1 sh reproduce/run_all.sh > "$OUT/run_all_full.out" 2>&1
echo "full (SKIP_BUILD=1): exit $?, $(( $(date +%s) - t0 )) s" >> "$OUT/header.txt"
keep "$OUT/results_full"

echo "# ended: $(date -Is)" >> "$OUT/header.txt"
touch "$OUT/DONE"
