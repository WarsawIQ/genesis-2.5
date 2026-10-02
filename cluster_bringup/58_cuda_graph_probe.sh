#!/bin/sh
# Does CUDA Graph dispatch (GENESIS_CUDA_GRAPH=1) make the repetitive GPU
# workloads faster? Measured, not argued: the reviewer of the SoftwareX
# revision asked about CUDA Graphs, and the answer should be a number.
#
# Graphs are on by default for the tree loop (since 2026-10-02) and off for the
# per-step dispatch; the arms here set GENESIS_CUDA_GRAPH explicitly, 0 = none
# and 1 = both, so they compare the same two paths as before.
#
# Two workloads, each with graphs off and on, replicates interleaved so that a
# drift of the node affects both arms alike:
#   tree     hh_multicompartment_createmap.g, N=10000 x 16 compartments,
#            K = 5000 and 50000 steps, batched tree loop (step phase timed by
#            the simulator, wall clock around the process)
#   spiking  VAnet2-batch-1solver.g on the GPU, per-step dispatch, wall clock
#
# Writes logs/cuda_graph_probe_<node>_<time>.csv with one row per run. Refuses
# to start on a GPU another process is using. Needs the CUDA build
# (cluster_bringup/10_build.sh).
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
R=$GENESIS_ROOT
cd "$R" || exit 1
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
export GENESIS_OCL_TREE_MAX_NCOMPTS=0
REPS=${REPS:-5}

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
[ "$USED" -gt 500 ] && { echo "ABORT: $USED MiB already allocated on $GPU" >&2; exit 1; }

OUT="$R/cluster_bringup/logs/cuda_graph_probe_$(hostname)_$(date +%Y%m%d_%H%M%S).csv"
echo "# commit: $(git rev-parse --short HEAD 2>/dev/null)" > "$OUT"
echo "# node: $(hostname)  gpu: $GPU  driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)" >> "$OUT"
echo "workload,n_steps,graph,rep,wall_s,step_s,graph_banner" >> "$OUT"

S=genesis/Scripts/benchmark/hh_multicompartment_createmap.g
tree_run() {   # $1 K, $2 graph 0|1, $3 rep
    t0=$(date +%s%N)
    o=$(env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 GENESIS_CUDA_MULTILOOP=$(($1 + 10)) \
          GENESIS_CUDA_GRAPH=$2 ./genesis/src/nxgenesis -nosimrc -notty -batch "$S" 10000 "$1" </dev/null 2>&1)
    t1=$(date +%s%N)
    step=$(echo "$o" | sed -n 's/^RESULT_T_TOTAL= *//p' | head -1)
    banner=$(echo "$o" | grep -c 'tree loop on')
    echo "tree,$1,$2,$3,$(awk "BEGIN{printf \"%.4f\", ($t1-$t0)/1e9}"),${step:-NA},$banner" >> "$OUT"
}

VA=$RUN_DIR/graph_probe_vanet2
rm -rf "$VA"; mkdir -p "$VA"
cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$VA"/
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
    "$R" "$R" "$R" "$RUN_DIR" "$R" > "$VA/.simrc"
spike_run() {  # $1 graph 0|1, $2 rep
    t0=$(date +%s%N)
    ( cd "$VA" && GENESIS_CUDA_GRAPH=$1 GENESIS_VANET2_SPIKEFILE="$VA/spikes_g$1_r$2.txt" \
        timeout 3600 "$R/genesis/src/nxgenesis" -notty -batch VAnet2-batch-1solver.g > "out_g$1_r$2.log" 2>&1 )
    t1=$(date +%s%N)
    banner=$(grep -c 'per-step on' "$VA/out_g$1_r$2.log")
    echo "spiking,100000,$1,$2,$(awk "BEGIN{printf \"%.4f\", ($t1-$t0)/1e9}"),NA,$banner" >> "$OUT"
}

for r in $(seq 1 "$REPS"); do
    for K in 5000 50000; do
        tree_run "$K" 0 "$r"; tree_run "$K" 1 "$r"
    done
    spike_run 0 "$r"; spike_run 1 "$r"
done

# Graphs must not change results: the spike trains of every run must agree.
n=$(for f in "$VA"/spikes_g*_r*.txt; do md5sum < "$f"; done | sort -u | wc -l)
echo "# distinct spike trains over all spiking runs: $n (1 means identical)" >> "$OUT"
echo "written: $OUT"
awk -F, '!/^#/ && NR>3 {k=$1","$2","$3; s[k]+=$5; c[k]++} END {for (k in s) printf "%s  mean wall %.3f s (n=%d)\n", k, s[k]/c[k], c[k]}' "$OUT" | sort
tail -1 "$OUT"
