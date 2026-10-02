#!/bin/bash
# A100 (inf03): base golden, F1+F2 checks (CUDA, OpenCL), CUDA Graphs probe.
set -u
T=$HOME/f1-test; F2=$HOME/genesis-2.5-f2; BASE=$HOME/genesis-2.5-git
echo "START $(date -Is) $(hostname) $(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader)"
cd $BASE && git log --oneline -1
sh cluster_bringup/10_build.sh > $T/a100_build_base.log 2>&1 || { echo "BASE BUILD FAILED"; exit 1; }
mkdir -p genesis/startup && cp -f $F2/genesis/startup/* genesis/startup/ 2>/dev/null || (cd genesis/src/startup && mkdir -p ../../startup && cp -f $(sed -n "s/^OBJS = //p" Makefile) ../../startup/)
ACCEL_GOLDEN=$T/golden_base_a100.txt sh cluster_bringup/80_accel_regression.sh record > $T/a100_record_base.log 2>&1; echo "base record rc=$?"
echo "base vs committed CUDA golden (A40, so a device mismatch is expected):"; sed -n "s/^# device: //p" $T/golden_base_a100.txt
cd $F2 && git log --oneline -1
sh cluster_bringup/10_build.sh > $T/a100_build_f2.log 2>&1 || { echo "F2 BUILD FAILED"; exit 1; }
ACCEL_GOLDEN=$T/golden_base_a100.txt sh cluster_bringup/80_accel_regression.sh check > $T/a100_f2_nograph.log 2>&1; echo "CUDA graphs off fp32 rc=$?"; tail -1 $T/a100_f2_nograph.log
GENESIS_CUDA_GRAPH=1 ACCEL_GOLDEN=$T/golden_base_a100.txt sh cluster_bringup/80_accel_regression.sh check > $T/a100_f2_graph.log 2>&1; echo "CUDA graphs on fp32 rc=$?"; tail -1 $T/a100_f2_graph.log
sh cluster_bringup/80_accel_regression.sh fp64 > $T/a100_f2_fp64.log 2>&1; echo "CUDA fp64 rc=$?"; tail -1 $T/a100_f2_fp64.log
GENESIS_CUDA_GRAPH=1 sh cluster_bringup/80_accel_regression.sh fp64 > $T/a100_f2_fp64_graph.log 2>&1; echo "CUDA fp64 graphs rc=$?"; tail -1 $T/a100_f2_fp64_graph.log
sh cluster_bringup/58_cuda_graph_probe.sh > $T/a100_probe.log 2>&1; echo "probe rc=$?"; tail -9 $T/a100_probe.log
# OpenCL
cd $BASE && sh cluster_bringup/11_build_opencl.sh > $T/a100_build_base_ocl.log 2>&1 && ACCEL_GOLDEN=$T/golden_base_a100_ocl.txt sh cluster_bringup/80_accel_regression.sh record > $T/a100_record_base_ocl.log 2>&1; echo "base ocl record rc=$?"
cd $F2 && sh cluster_bringup/11_build_opencl.sh > $T/a100_build_f2_ocl.log 2>&1 || { echo "F2 OCL BUILD FAILED"; exit 1; }
ACCEL_GOLDEN=$T/golden_base_a100_ocl.txt sh cluster_bringup/80_accel_regression.sh check > $T/a100_f2_ocl_fp32.log 2>&1; echo "OpenCL fp32 rc=$?"; tail -1 $T/a100_f2_ocl_fp32.log
sh cluster_bringup/80_accel_regression.sh fp64 > $T/a100_f2_ocl_fp64.log 2>&1; echo "OpenCL fp64 rc=$?"; tail -1 $T/a100_f2_ocl_fp64.log
sh cluster_bringup/10_build.sh > $T/a100_build_restore.log 2>&1 && echo "CUDA build restored"
echo "END $(date -Is)"
