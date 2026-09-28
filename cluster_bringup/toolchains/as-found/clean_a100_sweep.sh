#!/bin/bash
# Re-measure the A100 createmap sweep on an idle card.
#
# The original sweep (multicomp_walltime_hh_multicompartment_createmap_inf03_
# 20260815_223158.csv) is not trustworthy on its GPU arm: all ten N=50000
# replicates recorded ~1.8 ms, i.e. the binary never started, and a re-run on
# the idle card gives 8.02 s -- less than the 9.17 s the same sweep recorded at
# N=40000, which is impossible for a larger network. Something else was using
# the card, so the neighbouring points are inflated too and the whole GPU
# column has to be discarded rather than patched.
#
# This refuses to start on a busy card and re-runs the full sweep.
set -u
R="$HOME/genesis-2.5"
cd "$R" || exit 1
export LD_LIBRARY_PATH="/storage/opt/cuda/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}"

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
if [ "$USED" -gt 500 ]; then
    echo "ABORT: $USED MiB already allocated on $GPU" >&2
    exit 1
fi
echo "card idle ($USED MiB on $GPU), starting $(date +%T)"

BENCH_SCRIPT=hh_multicompartment_createmap REPS=10 STEPS=200 \
    sh cluster_bringup/54_multicomp_walltime.sh
