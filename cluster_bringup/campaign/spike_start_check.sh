#!/bin/sh
# Do the GPU paths emit spikes at the first step that the CPU does not?
#
#     sh cluster_bringup/campaign/spike_start_check.sh
#
# Found by E5 on v2.6.0-rc2 (2026-10-07): in the spiking network with one
# solver per layer, every one of the 4000 cells spiked at t = 50 us on the GPU,
# in fp32 and fp64, and none on the CPU. This runs a small VAnet2
# (GENESIS_VANET2_SCALE) for a short time on the CPU solver, CUDA fp32, CUDA
# fp64 and OpenCL, records every spike, and prints per arm the number of cells,
# the spikes in the first step and the time of the first spike, so a fix can be
# checked against the same numbers. It then runs hh_reset_rerun_check.g on each
# backend: a run, a RESET and the same run again must end at the same voltage
# (the CUDA backend used to carry its vm and gating state across RESET). Exit 0
# when no GPU arm spikes in a step where the CPU does not and every backend
# reruns identically after RESET.
#
# Writes logs/campaign_prep/spike_start_<node>_<time>.txt. Needs the binaries
# from prepare_node.sh.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
cd "$GENESIS_ROOT" || exit 2
[ -d "${CUDA_HOME:-}/lib64" ] && LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" && export LD_LIBRARY_PATH
SCALE=${SCALE:-20}       # 20 x 20 excitatory + 10 x 10 inhibitory = 500 cells
TMAX=${TMAX:-0.05}       # simulated seconds after the 0.05 s of driven input
OUT=cluster_bringup/logs/campaign_prep/spike_start_$(hostname -s)_$(date +%Y%m%d_%H%M%S).txt
mkdir -p "$(dirname "$OUT")"
W=$RUN_DIR/spike_start; rm -rf "$W"; mkdir -p "$W"

{
echo "# node $(hostname -s), $(git describe --tags --always), $(git rev-parse HEAD)"
echo "# VAnet2-batch-1solver.g, GENESIS_VANET2_SCALE=$SCALE, TMAX=$TMAX"
printf '%-10s %6s %8s %12s %14s\n' arm cells spikes first_step first_spike_s
} > "$OUT"

arm() {   # name, binary, extra env
    d="$W/$1"; mkdir -p "$d"
    cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$d"/
    printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
        "$GENESIS_ROOT" "$GENESIS_ROOT" "$GENESIS_ROOT" "$d" "$GENESIS_ROOT" > "$d/.simrc"
    ( cd "$d" && env GENESIS_VANET2_SCALE="$SCALE" GENESIS_VANET2_TMAX="$TMAX" \
          GENESIS_VANET2_SPIKEFILE="$d/spikes.txt" $3 \
          timeout 900 "$GENESIS_ROOT/genesis/src/$2" -notty -batch VAnet2-batch-1solver.g \
          > "$d/out.log" 2>&1 )
    awk -v a="$1" '{ t = $2 + 0; n++; c[$1] = 1; if (t < 6e-5) f++; if (n == 1 || t < m) m = t }
        END { nc = 0; for (k in c) nc++
              printf "%-10s %6d %8d %12d %14.6f\n", a, nc, n, f + 0, m }' "$d/spikes.txt" >> "$OUT"
    grep -m1 -E "^(CUDA: ready|OCL: gotowy)" "$d/out.log" | sed "s/^/#   $1: /" >> "$OUT"
}
arm cpu      nxgenesis_nocl ""
arm cuda32   nxgenesis      "GENESIS_GPU_PRECISION=fp32"
arm cuda64   nxgenesis      "GENESIS_GPU_PRECISION=fp64"
[ -x genesis/src/nxgenesis_ocl ] && arm ocl32 nxgenesis_ocl "GENESIS_GPU_PRECISION=fp32"
echo "# hh_reset_rerun_check.g: run, RESET, run again" >> "$OUT"
for a in "cpu nxgenesis_nocl" "cuda32 nxgenesis GENESIS_GPU_PRECISION=fp32" \
         "cuda64 nxgenesis GENESIS_GPU_PRECISION=fp64" "ocl32 nxgenesis_ocl GENESIS_GPU_PRECISION=fp32"; do
    set -- $a
    [ -x "genesis/src/$2" ] || continue
    r=$(env $3 timeout 600 ./genesis/src/$2 -nosimrc -notty -batch \
        genesis/Scripts/benchmark/hh_reset_rerun_check.g 8 300 </dev/null 2>&1 \
        | grep -E "^RESET_RERUN" | tr '\n' ' ')
    printf '%-10s %s\n' "$1" "${r:-NO RESULT}" >> "$OUT"
done
cat "$OUT"
echo "written: $OUT"
grep -q "RESET_RERUN: DIFFERENT\|NO RESULT" "$OUT" && exit 1
cpu_first=$(awk 'NF == 5 && $1 == "cpu" { print $4 }' "$OUT")
awk -v c="$cpu_first" 'NF == 5 && $2 ~ /^[0-9]+$/ && $1 != "cpu" && $4 != c { bad = 1 } END { exit bad }' "$OUT"
