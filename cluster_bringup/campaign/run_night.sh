#!/bin/sh
# One node's campaign plan for one night (research R7 of the campaign plan):
#
#     sh cluster_bringup/campaign/run_night.sh            # the plan for this node
#     sh cluster_bringup/campaign/run_night.sh E2 E8      # these stages only
#
# Default plans: inf03 runs E1 E5 E6 E7 (the stages that need one session on
# the A100 or its CPUs), then E2 E3 E4 E8 E3c; inf02 runs E2 E3 E4 E8. A stage
# that gives up on a busy GPU (3) or has rejected replicates (4) does not stop
# the night: the next stage runs, and the stopped one resumes its session when
# started again. Prints one status line per stage and writes them to
# logs/campaign_<tag>/night_<node>_<date>.txt. Never syncs or commits; that is
# done from the laptop with cluster_bringup/sync_from_cluster.sh.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$GENESIS_ROOT" || exit 2
NODE=${CAMPAIGN_NODE:-$(hostname -s)}
if [ $# -gt 0 ]; then PLAN="$*"
else
    case "$NODE" in
        inf03) PLAN="E1 E5 E6 E7 E2 E3 E4 E8 E3c" ;;
        inf02) PLAN="E2 E3 E4 E8" ;;
        *)     echo "no default plan for $NODE; name the stages" >&2; exit 2 ;;
    esac
fi
TAG=${CAMPAIGN_TAG:-v2.6.0-rc1}
OUT=cluster_bringup/logs/campaign_$TAG; [ "${CAMPAIGN_DRY:-0}" = 1 ] && OUT=cluster_bringup/logs/campaign_dry
mkdir -p "$OUT"
LOG="$OUT/night_${NODE}_$(date +%Y%m%d_%H%M%S).txt"
echo "# night on $NODE, $(git describe --tags --always), plan: $PLAN, started $(date -Is)" | tee "$LOG"
for e in $PLAN; do
    s=$(ls cluster_bringup/campaign/${e}_*.sh 2>/dev/null | head -1)
    [ -n "$s" ] || { echo "$e: no such stage" | tee -a "$LOG"; continue; }
    t0=$(date +%s)
    sh "$s" > "$OUT/${e}_${NODE}_last.log" 2>&1
    rc=$?
    case "$rc" in
        0) what="complete" ;;
        2) what="refused a precondition" ;;
        3) what="gave up on a busy GPU; rerun to resume" ;;
        4) what="replicates rejected twice; see rejected.csv" ;;
        *) what="failed" ;;
    esac
    printf '%-4s rc %s  %s  (%d min)\n' "$e" "$rc" "$what" $((($(date +%s) - t0) / 60)) | tee -a "$LOG"
done
echo "# ended $(date -Is)" | tee -a "$LOG"
