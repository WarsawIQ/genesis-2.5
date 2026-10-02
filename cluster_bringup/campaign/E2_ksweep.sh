#!/bin/sh
# E2: end-to-end speedup against run length, N = 10 000 trees x 16
# compartments, K = 200 ... 10 000 steps, CUDA fp32 and fp64 against the CPU
# solver, 5 replicates (reviewer points 8 and 4). The paper quotes one maximum
# end-to-end speedup, and it comes from here. Run on inf02 and on inf03.
# ~50 min per card, almost all of it the CPU arm.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-5}; N=10000; KLIST="200 500 1000 2000 5000 10000"
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && N=1000 && KLIST="200 1000"
campaign_init E2
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need_sass genesis/src/nxgenesis

arm() {   # cpu_k<K>, g32_k<K>, g64_k<K>
    k=${1##*_k}
    case "$1" in
        cpu_*) tree_rep "$1" "$2" "$3" cpu    "$N" "$k" 16 ;;
        g32_*) tree_rep "$1" "$2" "$3" cuda32 "$N" "$k" 16 ;;
        g64_*) tree_rep "$1" "$2" "$3" cuda64 "$N" "$k" 16 ;;
    esac
}
ARMS=""; RATIOS=""
for k in $KLIST; do
    ARMS="$ARMS cpu_k$k g32_k$k g64_k$k"
    RATIOS="$RATIOS e2e_fp32_k$k=cpu_k$k/g32_k$k e2e_fp64_k$k=cpu_k$k/g64_k$k fp64_cost_k$k=g64_k$k/g32_k$k"
done
run_arms "$REPS" arm $ARMS; st=$?
campaign_done "$st" $RATIOS
exit $st
