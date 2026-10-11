#!/bin/sh
# E9's 50 000-cell network under rusticl, one dispatch per step instead of one
# for the whole run.
#
#     sh cluster_bringup/campaign/e9_rusticl_perstep.sh <release checkout> [reps]
#
# On v2.6.0-rc4 E9's t1_rusticl_n50000 arm (hh_spiking_benchmark.g, N = 50 000,
# K = 50 000, GENESIS_OCL_MULTILOOP = K: the whole run in one dispatch) was
# reset by the amdgpu driver every time: rusticl runs on the graphics queue,
# whose lockup timeout (10 s) the single dispatch exceeds ("ring gfx timeout",
# "context is lost"); ROCm, on a compute queue, completed it. The
# single-compartment multiloop cannot be split (a smaller
# GENESIS_OCL_MULTILOOP would skip the remaining steps), so the way to run such
# a model under rusticl is without it, one short dispatch per step. This
# runs that, with the binary of <release checkout> built on the laptop, and
# records wall time and the result lines.
#
# Writes logs/campaign_prep/e9_rusticl_perstep_<host>_<time>/. Run on the
# laptop, on AC power, nothing else running.
set -u
[ $# -ge 1 ] || { echo "usage: $0 <release checkout> [reps]" >&2; exit 2; }
REL=$(cd "$1" && pwd)
REPS=${2:-2}
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
RUSTICL_ICD=${RUSTICL_ICD:-/etc/OpenCL/vendors/rusticl.icd}
N=${N:-50000}; K=${K:-50000}
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/e9_rusticl_perstep_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
BIN=$REL/genesis/src/nxgenesis_ocl
{
echo "# host $(hostname -s); binary $(cd "$REL" && git describe --tags --always) nxgenesis_ocl sha256 $(sha256sum "$BIN" | cut -d' ' -f1)"
echo "# hh_spiking_benchmark.g N=$N K=$K, rusticl ($RUSTICL_ICD), fp32, no GENESIS_OCL_MULTILOOP; power $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1)"
echo "rep,wall_s,exit,banner"
} > "$OUT/data.csv"
cd "$REL" || exit 2
for r in $(seq 1 "$REPS"); do
    log=$OUT/r$r.log
    t0=$(date +%s%N)
    env OCL_ICD_VENDORS="$RUSTICL_ICD" RUSTICL_ENABLE=radeonsi GENESIS_GPU_PRECISION=fp32 \
        timeout 3600 "$BIN" -nosimrc -notty -batch genesis/Scripts/benchmark/hh_spiking_benchmark.g \
        "$N" "$K" > "$log" 2>&1 < /dev/null
    rc=$?
    t1=$(date +%s%N)
    b=$(grep -m1 "^OCL: gotowy" "$log" | tr ',' ';')
    echo "$r,$(awk "BEGIN{printf \"%.3f\", ($t1 - $t0) / 1e9}"),$rc,$b" | tee -a "$OUT/data.csv"
done
echo "written: $OUT"
