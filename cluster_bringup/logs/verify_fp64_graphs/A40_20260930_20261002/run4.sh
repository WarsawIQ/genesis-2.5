#!/bin/bash
set -u
T=$HOME/f1-test; F1=$HOME/genesis-2.5-f1
echo "START $(date -Is)"
cd $F1 && sh cluster_bringup/11_build_opencl.sh > $T/build_f1_ocl2.log 2>&1 || { echo "F1 OCL BUILD FAILED"; exit 1; }
ACCEL_GOLDEN=$T/golden_base_ocl.txt sh cluster_bringup/80_accel_regression.sh check > $T/check_f1_ocl2_fp32.log 2>&1; echo "F1 ocl fp32 check rc=$?"; tail -3 $T/check_f1_ocl2_fp32.log
sh cluster_bringup/80_accel_regression.sh fp64 > $T/check_f1_ocl2_fp64.log 2>&1; echo "F1 ocl fp64 rc=$?"; tail -1 $T/check_f1_ocl2_fp64.log
. cluster_bringup/env.sh; GENESIS_GPU_PRECISION=double GENESIS_OCL_MULTILOOP=210 ./genesis/src/nxgenesis -nosimrc -notty -batch genesis/Scripts/benchmark/hh1952_ap_verify.g 8 200 </dev/null 2>&1 | grep -E "not understood|RESULT_VM"
sh cluster_bringup/10_build.sh > $T/build_f1_restore2.log 2>&1 && echo "CUDA build restored"
echo "END $(date -Is)"
