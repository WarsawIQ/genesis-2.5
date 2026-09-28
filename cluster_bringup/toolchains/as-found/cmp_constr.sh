#!/bin/sh
cd $HOME/genesis-2.5
export LD_LIBRARY_PATH=/storage/opt/cuda/cuda-12.8/lib64
for SCRIPT in hh_multicompartment_benchmark hh_multicompartment_createmap; do
  for M in cpu gpu; do
    if [ "$M" = cpu ]; then B=./genesis/src/nxgenesis_nocl; CM=1; E=""; else B=./genesis/src/nxgenesis; CM=4; E="GENESIS_CUDA_MULTILOOP=210"; fi
    S=$(date +%s%N)
    O=$(env GENESIS_BENCH_CHANMODE=$CM GENESIS_BENCH_NCOMP=16 $E $B -nosimrc -notty -batch \
        genesis/Scripts/benchmark/$SCRIPT.g 50000 200 2>&1)
    EN=$(date +%s%N)
    W=$(awk "BEGIN{printf \"%.2f\", ($EN-$S)/1e9}")
    T=$(echo "$O" | grep RESULT_T_TOTAL | awk -F= "{print \$2}" | tr -d " ")
    V=$(echo "$O" | grep RESULT_VM_SOMA | awk -F= "{print \$2}" | tr -d " ")
    echo "$SCRIPT $M wall=${W}s step=${T}s Vm=$V"
  done
done
