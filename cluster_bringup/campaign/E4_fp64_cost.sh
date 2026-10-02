#!/bin/sh
# E4: what double precision costs, and where the GENESIS/Arbor crossover moves
# when GENESIS also computes in double (Arbor always does): N = 10 000 trees x
# 16 compartments, K = 1000 ... 50 000, GENESIS CUDA fp32 and fp64 and Arbor on
# the same card, 3 replicates (reviewer point 4 and the double-precision caveat
# of the Arbor comparison). Run on inf02 and on inf03. ~25 min per card.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-3}; N=10000; KLIST="1000 2500 5000 10000 20000 50000"
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && N=1000 && KLIST="1000 5000"
campaign_init E4
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need_sass genesis/src/nxgenesis
sh cluster_bringup/coreneuron/arbor_check.sh > "$RUNS/arbor_check.log" 2>&1 \
    || { echo "REFUSED: Arbor does not load, see $RUNS/arbor_check.log" >&2; exit 2; }

arm() {   # g32_k<K>, g64_k<K>, arb_k<K>
    k=${1##*_k}
    case "$1" in
        g32_*) tree_rep "$1" "$2" "$3" cuda32 "$N" "$k" 16 ;;
        g64_*) tree_rep "$1" "$2" "$3" cuda64 "$N" "$k" 16 ;;
        arb_*) arbor_rep "$1" "$2" "$3" "$N" "$k" ;;
    esac
}
ARMS=""; RATIOS=""
for k in $KLIST; do
    ARMS="$ARMS g32_k$k g64_k$k arb_k$k"
    RATIOS="$RATIOS fp64_cost_k$k=g64_k$k/g32_k$k arbor_over_fp32_k$k=arb_k$k/g32_k$k arbor_over_fp64_k$k=arb_k$k/g64_k$k"
done
run_arms "$REPS" arm $ARMS; st=$?
campaign_done "$st" $RATIOS
exit $st
