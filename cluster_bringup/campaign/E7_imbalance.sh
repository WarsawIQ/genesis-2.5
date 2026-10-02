#!/bin/sh
# E7: work imbalance in the GPU tree kernel (reviewer point 6). The kernel runs
# one thread per tree, so a warp waits for its largest tree. Three populations
# with the same 360 000 compartments, N = 10 000, K = 2000, CUDA fp32:
#   uni36      every tree 36 compartments
#   mix_inter  trees of 8 and 64 alternating, so every warp holds both sizes
#   mix_block  the same trees in two blocks, so almost every warp is uniform
# plus the CPU solver on uni36 and mix_inter, whose times should agree (the same
# work), as the control that a GPU difference is imbalance and not work.
# Step-phase time (RESULT_T_PER_STEP) is the quantity; 5 replicates. inf03, ~30 min.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-5}; N=10000; K=2000
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && N=1000 && K=200
campaign_init E7
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need_sass genesis/src/nxgenesis
MIX="GENESIS_BENCH_NCOMP_MIX_A=8 GENESIS_BENCH_NCOMP_MIX_B=64"
arm() {
    case "$1" in
        gpu_uni36)     tree_rep "$1" "$2" "$3" cuda32 "$N" "$K" 36 ;;
        gpu_mix_inter) tree_rep "$1" "$2" "$3" cuda32 "$N" "$K" 8,64 $MIX GENESIS_BENCH_MIX_ORDER=0 ;;
        gpu_mix_block) tree_rep "$1" "$2" "$3" cuda32 "$N" "$K" 8,64 $MIX GENESIS_BENCH_MIX_ORDER=1 ;;
        cpu_uni36)     tree_rep "$1" "$2" "$3" cpu "$N" "$K" 36 ;;
        cpu_mix_inter) tree_rep "$1" "$2" "$3" cpu "$N" "$K" 8,64 $MIX GENESIS_BENCH_MIX_ORDER=0 ;;
    esac
}
run_arms "$REPS" arm gpu_uni36 gpu_mix_inter gpu_mix_block cpu_uni36 cpu_mix_inter; st=$?
# report.py takes ratios of wall time; the step-phase ratios come from the
# metric column (t_per_step_s) through the claim map.
campaign_done "$st" "inter_over_uniform_gpu=gpu_mix_inter/gpu_uni36" \
    "inter_over_block_gpu=gpu_mix_inter/gpu_mix_block" "inter_over_uniform_cpu=cpu_mix_inter/cpu_uni36"
exit $st
