#!/bin/sh
# CPU against GPU on spike count for the Vogels-Abbott network, which is the
# agreement the paper reports. Both arms record every spike; neither is timed.
#
#     sh cluster_bringup/coreneuron/spike_compare.sh
#     BIN_GPU=genesis/src/nxgenesis.sm86 sh cluster_bringup/coreneuron/spike_compare.sh
#
# From as-found/spike_compare.sh and spike_compare_a40.sh, which differed only
# in the GPU binary (the A40 run used one built for sm_86). The counts are now
# also written to a CSV under logs/, not only printed.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
R="$GENESIS_ROOT"
BIN_GPU=${BIN_GPU:-genesis/src/nxgenesis}
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
OUT="$R/cluster_bringup/logs/spike_compare_$(hostname)_$(date +%Y%m%d_%H%M%S).csv"
echo "node,gpu,arm,binary,spikes" > "$OUT"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
for arm in cpu gpu; do
    bin=$R/genesis/src/nxgenesis_nocl
    [ "$arm" = gpu ] && bin=$R/$BIN_GPU
    D=$RUN_DIR/spikecmp-$arm; rm -rf "$D"; mkdir -p "$D"
    cp "$R"/genesis/Scripts/VAnet2/*.g "$R"/genesis/Scripts/VAnet2/*.p "$D"/
    printf "setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n" "$R" "$R" "$R" "$D" "$R" > "$D/.simrc"
    ( cd "$D" && GENESIS_VANET2_SPIKEFILE="$D/spikes.txt" timeout 3600 "$bin" -notty -batch VAnet2-batch-1solver.g > out.log 2>&1 )
    n=$(wc -l < "$D/spikes.txt" 2>/dev/null || echo 0)
    echo "$arm spikes=$n"
    echo "$(hostname),$GPU,$arm,$(basename "$bin"),$n" >> "$OUT"
done
echo "written: $OUT"
