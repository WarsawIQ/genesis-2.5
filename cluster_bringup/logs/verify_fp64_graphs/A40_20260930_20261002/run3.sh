#!/bin/bash
set -u
T=$HOME/f1-test; F1=$HOME/genesis-2.5-f1; BASE=$HOME/genesis-2.5-git
echo "START $(date -Is) $(hostname) $(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader)"
cd $BASE && sh cluster_bringup/11_build_opencl.sh > $T/build_base_ocl.log 2>&1 || { echo "BASE OCL BUILD FAILED"; tail -5 $T/build_base_ocl.log; exit 1; }
mkdir -p genesis/startup && cp -f $F1/genesis/startup/* genesis/startup/
ACCEL_GOLDEN=$T/golden_base_ocl.txt sh cluster_bringup/80_accel_regression.sh record > $T/record_base_ocl.log 2>&1; echo "base ocl record rc=$?"
echo "vs committed opencl golden:"; diff <(grep -v "^#" cluster_bringup/accel_regression_golden_opencl.txt) <(grep -v "^#" $T/golden_base_ocl.txt) && echo "  identical" || echo "  differs"
cd $F1 && sh cluster_bringup/11_build_opencl.sh > $T/build_f1_ocl.log 2>&1 || { echo "F1 OCL BUILD FAILED"; tail -5 $T/build_f1_ocl.log; exit 1; }
ACCEL_GOLDEN=$T/golden_base_ocl.txt sh cluster_bringup/80_accel_regression.sh check > $T/check_f1_ocl_fp32.log 2>&1; echo "F1 ocl fp32 check rc=$?"; tail -3 $T/check_f1_ocl_fp32.log
sh cluster_bringup/80_accel_regression.sh fp64 > $T/check_f1_ocl_fp64.log 2>&1; echo "F1 ocl fp64 rc=$?"; grep -E "RESULT|PASS|FAIL|reported" $T/check_f1_ocl_fp64.log
# back to the CUDA build for later work
sh cluster_bringup/10_build.sh > $T/build_f1_restore.log 2>&1 && echo "CUDA build restored"
echo "END $(date -Is)"
