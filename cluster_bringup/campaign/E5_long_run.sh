#!/bin/sh
# E5: is fp32 adequate over a long run? The spiking network for 10 s simulated
# (GENESIS_VANET2_TMAX = 9.95 after the 0.05 s of driven input), one solver per
# layer, on the CPU (fp64), CUDA fp32 and CUDA fp64, 3 replicates, every spike
# recorded (reviewer point 4). spikes_compare.py then reports spike counts,
# rates, ISI distributions and the time at which each run first departs from
# the CPU's spike train. Recording every spike slows the runs, so their wall
# times are not speed results. Run on inf03. ~25 min.
#
# The spike files are large (about a million spikes each). The repository keeps
# the comparison table, the checksum of every file and, compressed, the first
# replicate of each arm.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-3}; TMAX=9.95; SCALE=""
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && TMAX=0.45
campaign_init E5
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need_sass genesis/src/nxgenesis
W="$RUN_DIR/campaign_E5"
for a in cpu g32 g64; do vanet2_workdir "$W/$a"; done
spikes_in_file() { wc -l < "$SPIKEFILE_CUR"; }

arm() {
    SPIKEFILE_CUR="$W/$1/spikes_r$2.txt"; rm -f "$SPIKEFILE_CUR"
    SPIKES_OF=spikes_in_file EXPECT_NCOMP=4000
    case "$1" in
        cpu) b=$BANNER_CPU;    bin=nxgenesis_nocl; p=fp32 ;;
        g32) b=$BANNER_CUDA32; bin=nxgenesis;      p=fp32 ;;
        g64) b=$BANNER_CUDA64; bin=nxgenesis;      p=fp64 ;;
    esac
    g=1; [ "$1" = cpu ] && g=0
    run_rep "$1" "$2" "$3" "$g" "$b" sanity_spikes \
        env -C "$W/$1" GENESIS_VANET2_TMAX="$TMAX" GENESIS_VANET2_SPIKEFILE="$SPIKEFILE_CUR" \
        GENESIS_GPU_PRECISION=$p timeout 7200 "$GENESIS_ROOT/genesis/src/$bin" -notty -batch VAnet2-batch-1solver.g
}
run_arms "$REPS" arm cpu g32 g64; st=$?

# compare every replicate with the first CPU replicate
args="cpu_r1=$W/cpu/spikes_r1.txt"
for a in cpu g32 g64; do
    r=1
    while [ "$r" -le "$REPS" ]; do
        [ "$a$r" = cpu1 ] || { [ -f "$W/$a/spikes_r$r.txt" ] && args="$args ${a}_r$r=$W/$a/spikes_r$r.txt"; }
        r=$((r + 1))
    done
done
CMP="${CSV%.csv}_spikes.csv"
python3 cluster_bringup/campaign/spikes_compare.py "$CMP" 4000 "$(awk "BEGIN{print $TMAX + 0.05}")" $args \
    | tee "${CSV%.csv}_spikes.txt"
( cd "$W" && sha256sum */spikes_r*.txt ) > "${CSV%.csv}_spikes.sha256"
for a in cpu g32 g64; do
    [ -f "$W/$a/spikes_r1.txt" ] && gzip -9c "$W/$a/spikes_r1.txt" > "$RUNS/${a}_spikes_r1.txt.gz"
done
campaign_done "$st" "gpu32_over_cpu=g32/cpu" "gpu64_over_gpu32=g64/g32"
exit $st
