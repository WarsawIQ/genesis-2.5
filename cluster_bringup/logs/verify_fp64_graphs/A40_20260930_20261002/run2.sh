#!/bin/bash
set -u
T=$HOME/f1-test; F1=$HOME/genesis-2.5-f1; BASE=$HOME/genesis-2.5-git
echo "START $(date -Is) $(hostname) $(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader)"
cd $F1 && sh cluster_bringup/10_build.sh > $T/build_f1b.log 2>&1 || { echo "F1 BUILD FAILED"; exit 1; }
ls genesis/startup | wc -l
# base binaries are still built in $BASE; give it the startup files and re-record
mkdir -p $BASE/genesis/startup && cp -f $F1/genesis/startup/* $BASE/genesis/startup/
cd $BASE && ACCEL_GOLDEN=$T/golden_base2.txt sh cluster_bringup/80_accel_regression.sh record > $T/record_base2.log 2>&1; echo "base re-record rc=$?"
echo "vanet2 md5: base=$(grep vanet2_cpu.vm_md5 $T/golden_base2.txt | cut -d= -f2) august=$(grep vanet2_cpu.vm_md5 $BASE/cluster_bringup/accel_regression_golden.txt | cut -d= -f2)"
cd $F1 && ACCEL_GOLDEN=$T/golden_base2.txt sh cluster_bringup/80_accel_regression.sh check > $T/check_f1b_fp32.log 2>&1; echo "F1 fp32 check rc=$?"; tail -1 $T/check_f1b_fp32.log
sh cluster_bringup/80_accel_regression.sh fp64 > $T/check_f1b_fp64.log 2>&1; echo "F1 fp64 check rc=$?"; grep -E "RESULT|PASS|FAIL" $T/check_f1b_fp64.log
# same code, nvcc told not to contract multiply-adds
. cluster_bringup/env.sh; cd genesis/src; export PATH=$CUDA_HOME/bin:$PATH
rm -f hines/cuda/*.o hines/hineslib.o nxgenesis
make USE_CUDA=1 CUDA_HOME=$CUDA_HOME NVCCFLAGS="-arch=sm_86 -ccbin $(command -v gcc) -fmad=false" EXTRALIBS="sprng/lib/liblfg.a -lncurses -ltinfo -lOpenCL -L$CUDA_HOME/lib64 -lcudart -lstdc++" LEXLIB=$F1/locallib/libfl.a nxgenesis > $T/build_nofma.log 2>&1 || { echo "NOFMA BUILD FAILED"; tail -5 $T/build_nofma.log; exit 1; }
cd $F1 && sh cluster_bringup/80_accel_regression.sh fp64 > $T/check_f1b_fp64_nofma.log 2>&1; echo "F1 fp64 -fmad=false rc=$?"; grep -E "RESULT|PASS|FAIL" $T/check_f1b_fp64_nofma.log
# put the normal build back
sh cluster_bringup/10_build.sh > $T/build_f1c.log 2>&1 && echo "normal build restored"
echo "END $(date -Is)"
