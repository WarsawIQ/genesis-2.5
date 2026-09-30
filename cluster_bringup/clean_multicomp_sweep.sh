#!/bin/bash
# Re-measure the end-to-end createmap sweep (Table 2, Fig. 10) on an idle card.
#
# The first sweep (logs/multicomp_walltime_hh_multicompartment_createmap_inf03_
# 20260815_223158.csv) is not trustworthy on its GPU arm: all ten N=50000
# replicates recorded ~1.8 ms, i.e. the binary never started, and a re-run on
# the idle card gives 8.02 s -- less than the 9.17 s the same sweep recorded at
# N=40000, which is impossible for a larger network. Something else was using
# the card, so the neighbouring points are inflated too and the whole GPU
# column has to be discarded rather than patched.
#
# This refuses to start on a busy card and re-runs the full sweep. Run it on
# the node whose card is to be measured; the card is taken from nvidia-smi.
#
# From as-found/clean_a40_sweep.sh and clean_a100_sweep.sh, which differed only
# in the name of the card in their first comment line.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 1
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
if [ "$USED" -gt 500 ]; then
    echo "ABORT: $USED MiB already allocated on $GPU" >&2
    exit 1
fi
echo "card idle ($USED MiB on $GPU), starting $(date +%T)"

BENCH_SCRIPT=hh_multicompartment_createmap REPS=10 STEPS=200 \
    sh cluster_bringup/54_multicomp_walltime.sh
