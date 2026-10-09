#!/bin/sh
# How much of a tree-loop step is host work and how much is kernel time?
#
#     sh cluster_bringup/campaign/host_kernel_profile.sh <release checkout>
#
# The paper's execution-model paragraph compares the host's cost of issuing a
# step with the kernels' time per step. Wall time cannot split the two, so this
# runs E8's tree workload (N = 10 000 trees of 16 compartments, chanmode 4,
# K steps in one batched tree loop) under Nsight Systems, once with CUDA Graphs
# off and once on, and keeps nsys's summaries of the kernels (GPU time) and of
# the CUDA API calls (host time). Per step:
#   kernel time  = total time of the tree loop's kernels / K
#   host time    = total time of the launch calls (cudaLaunchKernel with graphs
#                  off, cudaGraphLaunch with graphs on) / K
#
# The binary comes from <release checkout>, built by prepare_node.sh on the
# campaign tag; its describe and sha256 are recorded, so the numbers belong to
# that tag even though this script is newer. Needs nsys ($CUDA_HOME/bin).
# Writes logs/campaign_prep/host_kernel_<node>_<time>/: the nsys reports, the
# two summaries per run as CSV, the run logs and run.txt.
set -u
[ $# -eq 1 ] || { echo "usage: $0 <release checkout>" >&2; exit 2; }
REL=$(cd "$1" && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
[ -d "${CUDA_HOME:-}/lib64" ] && LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" && export LD_LIBRARY_PATH
# as cuda_env in lib.sh: above 20 000 compartments the batched tree solver
# would otherwise decline the model and fall back to per-step dispatch
export GENESIS_OCL_TREE_MAX_NCOMPTS=0
NSYS=${NSYS:-$CUDA_HOME/bin/nsys}
[ -x "$NSYS" ] || { echo "no nsys at $NSYS" >&2; exit 2; }
BIN=$REL/genesis/src/nxgenesis
[ -x "$BIN" ] || { echo "no $BIN: run prepare_node.sh in $REL" >&2; exit 2; }
N=${N:-10000}; K=${K:-5000}
NUMA=${CAMPAIGN_NUMA:-0}
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/host_kernel_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
{
echo "# node $(hostname -s), gpu $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
echo "# binary $BIN"
echo "# binary from $(cd "$REL" && git describe --tags --always --dirty) $(cd "$REL" && git rev-parse HEAD)"
echo "# binary sha256 $(sha256sum "$BIN" | cut -d' ' -f1)"
echo "# script from $(git -C "$GENESIS_ROOT" describe --tags --always --dirty)"
echo "# nsys $("$NSYS" --version 2>&1 | head -1)"
echo "# N=$N trees x 16 compartments, K=$K steps, chanmode 4, numactl node $NUMA"
} > "$OUT/run.txt"

cd "$REL" || exit 2
for g in 0 1; do
    numactl --cpunodebind="$NUMA" --membind="$NUMA" \
        "$NSYS" profile --trace=cuda --sample=none --cpuctxsw=none --force-overwrite=true \
        -o "$OUT/tree_g$g" \
        env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 GENESIS_CUDA_MULTILOOP=$((K + 10)) \
        GENESIS_CUDA_GRAPH="$g" "$BIN" -nosimrc -notty -batch \
        genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$N" "$K" > "$OUT/tree_g$g.log" 2>&1
    rc=$?
    m=$(grep -m1 'CUDA MULTILOOP (tree)' "$OUT/tree_g$g.log")
    echo "graphs $g: exit $rc, ${m:-NO TREE LOOP: the run did not take the batched path}" >> "$OUT/run.txt"
    for r in cuda_gpu_kern_sum cuda_api_sum; do
        "$NSYS" stats --report "$r" --format csv --force-export=true --output "$OUT/tree_g$g" \
            "$OUT/tree_g$g.nsys-rep" > /dev/null 2>> "$OUT/run.txt"
    done
done
rm -f "$OUT"/*.sqlite
ls "$OUT" >> "$OUT/run.txt"
cat "$OUT/run.txt"
echo "written: $OUT"
