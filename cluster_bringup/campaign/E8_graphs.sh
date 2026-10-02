#!/bin/sh
# E8: CUDA Graphs off and on, on the release tag (reviewer point 6), the
# measurement of 58_cuda_graph_probe.sh under the campaign harness:
#   tree_k5000_g0/g1, tree_k50000_g0/g1   N = 10 000 x 16, batched tree loop
#   spk_g0/g1                             the spiking network on the GPU, per-step path
# g0 = GENESIS_CUDA_GRAPH=0 (no graphs), g1 = 1 (tree loop and per-step path).
# The release default is graphs for the tree loop only, which is g1 for the
# tree workload and g0 for the spiking one. Timing runs record no spikes; one
# extra run of each spiking arm records them, and the two trains must be
# identical. 5 replicates; inf02 and inf03, ~20 min each.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-5}; N=10000; KS="5000 50000"
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && N=1000 && KS="500"
campaign_init E8
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need_sass genesis/src/nxgenesis
W="$RUN_DIR/campaign_E8"; vanet2_workdir "$W"
B0='^CUDA: graph dispatch: tree loop off, per-step off'
B1='^CUDA: graph dispatch: tree loop on, per-step on'
spikes_in_file() { wc -l < "$SPIKEFILE_CUR"; }

arm() {
    g=${1##*_g}
    b=$B0; [ "$g" = 1 ] && b=$B1
    case "$1" in
    tree_k*)
        k=${1#tree_k}; k=${k%_g*}
        EXPECT_N=$N EXPECT_STEPS=$k EXPECT_NCOMP=16
        run_rep "$1" "$2" "$3" 1 "$b" sanity_tree \
            env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 GENESIS_CUDA_MULTILOOP=$((k + 10)) \
            GENESIS_CUDA_GRAPH="$g" timeout 3600 ./genesis/src/nxgenesis -nosimrc -notty -batch \
            genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$N" "$k" ;;
    spk_id_g*)
        SPIKEFILE_CUR="$W/spikes_g$g.txt"; rm -f "$SPIKEFILE_CUR"; SPIKES_OF=spikes_in_file
        run_rep "$1" "$2" "$3" 1 "$b" sanity_spikes \
            env -C "$W" GENESIS_CUDA_GRAPH="$g" GENESIS_VANET2_SPIKEFILE="$SPIKEFILE_CUR" \
            timeout 3600 "$GENESIS_ROOT/genesis/src/nxgenesis" -notty -batch VAnet2-batch-1solver.g ;;
    spk_g*)
        EXPECT_NCOMP=4000
        run_rep "$1" "$2" "$3" 1 "$b" sanity_vanet2 \
            env -C "$W" GENESIS_CUDA_GRAPH="$g" \
            timeout 3600 "$GENESIS_ROOT/genesis/src/nxgenesis" -notty -batch VAnet2-batch-1solver.g ;;
    esac
}
ARMS=""; RATIOS=""
for k in $KS; do ARMS="$ARMS tree_k${k}_g0 tree_k${k}_g1"; RATIOS="$RATIOS gain_tree_k$k=tree_k${k}_g0/tree_k${k}_g1"; done
ARMS="$ARMS spk_g0 spk_g1"; RATIOS="$RATIOS gain_spiking=spk_g0/spk_g1"
run_arms "$REPS" arm $ARMS; st=$?
arm spk_id_g0 1 1 || st=$?
arm spk_id_g1 1 2 || st=$?
if [ -f "$W/spikes_g0.txt" ] && [ -f "$W/spikes_g1.txt" ]; then
    if cmp -s "$W/spikes_g0.txt" "$W/spikes_g1.txt"; then same=identical; else same=DIFFERENT; st=4; fi
    echo "spike trains with graphs off and on: $same ($(wc -l < "$W/spikes_g0.txt") spikes)" \
        | tee -a "$RUNS/notes"
fi
campaign_done "$st" --single=spk_id_g0,spk_id_g1 $RATIOS
exit $st
