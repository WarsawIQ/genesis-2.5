#!/bin/bash
set -u
T=$HOME/f1-test; F2=$HOME/genesis-2.5-f2
echo "START $(date -Is) $(hostname) $(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader)"
cd $F2 && sh cluster_bringup/10_build.sh > $T/build_f2.log 2>&1 || { echo "F2 BUILD FAILED"; grep -n -i error $T/build_f2.log | head; exit 1; }
ACCEL_GOLDEN=$T/golden_base2.txt sh cluster_bringup/80_accel_regression.sh check > $T/f2_check_nograph.log 2>&1; echo "graphs off, fp32 check rc=$?"; tail -1 $T/f2_check_nograph.log
GENESIS_CUDA_GRAPH=1 ACCEL_GOLDEN=$T/golden_base2.txt sh cluster_bringup/80_accel_regression.sh check > $T/f2_check_graph.log 2>&1; echo "graphs on, fp32 check rc=$?"; tail -1 $T/f2_check_graph.log
GENESIS_CUDA_GRAPH=1 sh cluster_bringup/80_accel_regression.sh fp64 > $T/f2_fp64_graph.log 2>&1; echo "graphs on, fp64 rc=$?"; tail -1 $T/f2_fp64_graph.log
sh cluster_bringup/58_cuda_graph_probe.sh > $T/f2_probe.log 2>&1; echo "probe rc=$?"; tail -9 $T/f2_probe.log
echo "END $(date -Is)"
