#!/bin/sh
# How far apart are two CPU runs of VAnet2 that differ only in something that
# should not matter? The yardstick for the CUDA-vs-CPU spike-train difference.
#
#     sh cluster_bringup/campaign/spike_variability_check.sh
#
# The CUDA solver delivers every spike at the next step; the CPU solver
# delivers a spike to compartments later in its loop within the same step. The
# two runs of the full network therefore part at 2.65 ms and from then on are
# different trajectories of a chaotic network (logs/campaign_prep/
# spikes_full_inf03_20261008). Whether the CUDA rate and ISI distribution
# differ from the CPU's by more than the model itself varies is measured here,
# all on the fp64 CPU solver (nxgenesis_nocl), full network, 5 s:
#
#   cpu        VAnet2-batch-1solver.g, published seed: the reference
#   percell    VAnet2-batch.g, one solver per cell: the same network and seed,
#              a different update order
#   seed1..4   VAnet2-batch-1solver.g with GENESIS_VANET2_SEED=1..4: other
#              draws of the connections and of the input spikes
#
# The arms run in parallel, one core each. Writes logs/campaign_prep/
# spike_variability_<node>_<time>/ with the gzipped spike files, compare.csv
# (spikes_compare.py against cpu) and run.txt. Needs nxgenesis_nocl from
# prepare_node.sh.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 2
TMAX=${TMAX:-4.95}
SEEDS=${SEEDS:-1 2 3 4}
OUT=cluster_bringup/logs/campaign_prep/spike_variability_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
W=$RUN_DIR/spike_variability; rm -rf "$W"; mkdir -p "$W"
BIN=$GENESIS_ROOT/genesis/src/nxgenesis_nocl
[ -x "$BIN" ] || { echo "no $BIN: run prepare_node.sh" >&2; exit 2; }

{
echo "# node $(hostname -s), $(git describe --tags --always --dirty), $(git rev-parse HEAD)"
echo "# binary $BIN, sha256 $(sha256sum "$BIN" | cut -d' ' -f1)"
echo "# TMAX=$TMAX, seeds: $SEEDS"
} > "$OUT/run.txt"

arm() {   # name, script, extra env
    d="$W/$1"; mkdir -p "$d"
    cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$d"/
    printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
        "$GENESIS_ROOT" "$GENESIS_ROOT" "$GENESIS_ROOT" "$d" "$GENESIS_ROOT" > "$d/.simrc"
    ( cd "$d" && env GENESIS_VANET2_TMAX="$TMAX" GENESIS_VANET2_SPIKEFILE="$d/spikes.txt" ${3:-} \
          timeout 3600 "$BIN" -notty -batch "$2" > "$d/out.log" 2>&1
      echo "$1: exit $? $(grep -m1 'VAnet2 seed' "$d/out.log")" >> "$OUT/run.txt" )
}
arm cpu     VAnet2-batch-1solver.g &
arm percell VAnet2-batch.g &
for s in $SEEDS; do arm seed$s VAnet2-batch-1solver.g "GENESIS_VANET2_SEED=$s" & done
wait

set -- cpu="$OUT/cpu.txt.gz" percell="$OUT/percell.txt.gz"
for s in $SEEDS; do set -- "$@" seed$s="$OUT/seed$s.txt.gz"; done
for a in cpu percell $(for s in $SEEDS; do echo seed$s; done); do
    gzip -9c "$W/$a/spikes.txt" > "$OUT/$a.txt.gz"
done
python3 cluster_bringup/campaign/spikes_compare.py "$OUT/compare.csv" 4000 "$(awk -v t="$TMAX" 'BEGIN { print t + 0.05 }')" "$@" \
    | tee -a "$OUT/run.txt"
echo "written: $OUT"
