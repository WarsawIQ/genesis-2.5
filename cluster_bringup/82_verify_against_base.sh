#!/bin/bash
# Verify a change to the accelerator against the code before it, on one card.
#
#     BASE=<checkout of the base commit> sh cluster_bringup/82_verify_against_base.sh
#
# Run it from the checkout under test, on the GPU node to be checked. It builds
# the base checkout and records a fresh golden from it (goldens are per device:
# fp32 kernels are not bit-identical across cards, and a committed golden may be
# older than the base), then builds this checkout and checks it against that
# golden, with CUDA Graphs off and on, then the fp64 mode, then the same for
# OpenCL, and finally the CUDA Graphs probe. Every output goes to
# logs/verify_against_base/<node>_<time>/, with the commits named, so the whole
# check can be repeated and its result read from the repository.
#
# Written after the fp64 and CUDA Graphs work had been checked with one-off
# driver scripts on the cluster; those scripts and their outputs are kept in
# logs/verify_fp64_graphs/, and this is the same procedure as one script.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
HEAD_DIR=$GENESIS_ROOT
BASE=${BASE:?set BASE to a checkout of the commit to compare against}
PROBE=${PROBE:-1}
GPU=$(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader | head -1)
case "$GPU" in *", 0 MiB") ;; *) echo "ABORT: GPU in use: $GPU" >&2; exit 1 ;; esac

T="$HEAD_DIR/cluster_bringup/logs/verify_against_base/$(hostname)_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$T"
log() { echo "$*" | tee -a "$T/summary.txt"; }
log "node $(hostname)  gpu $GPU  started $(date -Is)"
log "base $(git -C "$BASE" rev-parse --short HEAD)  head $(git -C "$HEAD_DIR" rev-parse --short HEAD)"

startup() {   # genesis/startup, as the build scripts now do, for an older base
    (cd "$1/genesis/src/startup" && mkdir -p ../../startup \
        && cp -f $(sed -n 's/^OBJS = //p' Makefile) ../../startup/)
}

for backend in cuda opencl; do
    build=10_build.sh; [ "$backend" = opencl ] && build=11_build_opencl.sh
    (cd "$BASE" && sh cluster_bringup/$build > "$T/build_base_$backend.log" 2>&1) \
        || { log "base $backend build FAILED"; exit 1; }
    startup "$BASE"
    (cd "$BASE" && ACCEL_GOLDEN="$T/golden_base_$backend.txt" \
        sh cluster_bringup/80_accel_regression.sh record > "$T/record_base_$backend.log" 2>&1)
    log "$backend base golden recorded (rc $?)"
    (cd "$HEAD_DIR" && sh cluster_bringup/$build > "$T/build_head_$backend.log" 2>&1) \
        || { log "head $backend build FAILED"; exit 1; }
    cd "$HEAD_DIR"
    ACCEL_GOLDEN="$T/golden_base_$backend.txt" sh cluster_bringup/80_accel_regression.sh check \
        > "$T/check_${backend}_fp32.log" 2>&1
    log "$backend fp32 vs base: rc $?  $(tail -1 "$T/check_${backend}_fp32.log")"
    sh cluster_bringup/80_accel_regression.sh fp64 > "$T/check_${backend}_fp64.log" 2>&1
    log "$backend fp64 vs CPU:  rc $?  $(tail -1 "$T/check_${backend}_fp64.log")"
    if [ "$backend" = cuda ]; then
        GENESIS_CUDA_GRAPH=1 ACCEL_GOLDEN="$T/golden_base_$backend.txt" \
            sh cluster_bringup/80_accel_regression.sh check > "$T/check_cuda_fp32_graphs.log" 2>&1
        log "cuda fp32 graphs on:   rc $?  $(tail -1 "$T/check_cuda_fp32_graphs.log")"
        GENESIS_CUDA_GRAPH=1 sh cluster_bringup/80_accel_regression.sh fp64 \
            > "$T/check_cuda_fp64_graphs.log" 2>&1
        log "cuda fp64 graphs on:   rc $?  $(tail -1 "$T/check_cuda_fp64_graphs.log")"
        if [ "$PROBE" = 1 ]; then
            sh cluster_bringup/58_cuda_graph_probe.sh > "$T/graph_probe.log" 2>&1
            log "graph probe: rc $?  $(grep -o 'written: .*' "$T/graph_probe.log")"
        fi
    fi
done
(cd "$HEAD_DIR" && sh cluster_bringup/10_build.sh > "$T/build_restore.log" 2>&1) && log "CUDA build restored"
gzip -9 "$T"/build_*.log
log "finished $(date -Is)"
