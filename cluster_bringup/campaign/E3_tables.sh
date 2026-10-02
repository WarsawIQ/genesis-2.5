#!/bin/sh
# E3, GPU part: the single-compartment table (Table 1: N = 500, 5000, 50 000,
# K = 50 000, CUDA and OpenCL against the CPU) and the dendritic-tree sweep
# (Table 2 and Fig. 10: N = 100 ... 50 000 x 16 compartments, K = 200, end to
# end and step phase), 10 replicates each, OpenCL now as many as CUDA
# (reviewer point 8). Run on inf02 and on inf03. ~60 min per card.
#
# Needs both binaries: cluster_bringup/11_build_opencl.sh (nxgenesis_ocl), then
# cluster_bringup/10_build.sh (nxgenesis with CUDA, nxgenesis_nocl).
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-10}
T1_N="500 5000 50000"; T1_K=50000
T2_N="100 500 1000 2000 3000 5000 7000 10000 15000 20000 30000 40000 50000"; T2_K=200
if [ "$CAMPAIGN_DRY" = 1 ]; then
    REPS=${REPS_DRY:-1}; T1_N="500"; T1_K=5000; T2_N="100 1000"
fi
campaign_init E3
cuda_env
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_ocl "cluster_bringup/11_build_opencl.sh, before 10_build.sh"
need_sass genesis/src/nxgenesis
S1=genesis/Scripts/benchmark/hh_spiking_benchmark.g

single() {   # <arm> <rep> <order> <cpu|cuda|ocl> <N>: Table 1, as 53_ and 56_ ran it
    EXPECT_N=$5 EXPECT_STEPS=$T1_K
    case "$4" in
        cpu)  run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_single \
                  timeout 1800 ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch "$S1" "$5" "$T1_K" ;;
        cuda) run_rep "$1" "$2" "$3" 1 "$BANNER_CUDA32" sanity_single \
                  env GENESIS_CUDA_MULTILOOP="$T1_K" \
                  timeout 1800 ./genesis/src/nxgenesis -nosimrc -notty -batch "$S1" "$5" "$T1_K" ;;
        ocl)  run_rep "$1" "$2" "$3" 1 "$BANNER_OCL32" sanity_single \
                  env GENESIS_OCL_MULTILOOP="$T1_K" \
                  timeout 1800 ./genesis/src/nxgenesis_ocl -nosimrc -notty -batch "$S1" "$5" "$T1_K" ;;
    esac
}
arm() {   # t1_<be>_n<N>, t2_<be>_n<N>
    n=${1##*_n}
    case "$1" in
        t1_cpu_*)  single "$1" "$2" "$3" cpu "$n" ;;
        t1_cuda_*) single "$1" "$2" "$3" cuda "$n" ;;
        t1_ocl_*)  single "$1" "$2" "$3" ocl "$n" ;;
        t2_cpu_*)  tree_rep "$1" "$2" "$3" cpu    "$n" "$T2_K" 16 ;;
        t2_cuda_*) tree_rep "$1" "$2" "$3" cuda32 "$n" "$T2_K" 16 ;;
        t2_ocl_*)  tree_rep "$1" "$2" "$3" ocl32  "$n" "$T2_K" 16 ;;
    esac
}
ARMS=""; RATIOS=""
for n in $T1_N; do
    ARMS="$ARMS t1_cpu_n$n t1_cuda_n$n t1_ocl_n$n"
    RATIOS="$RATIOS t1_cuda_n$n=t1_cpu_n$n/t1_cuda_n$n t1_ocl_n$n=t1_cpu_n$n/t1_ocl_n$n"
done
for n in $T2_N; do
    ARMS="$ARMS t2_cpu_n$n t2_cuda_n$n t2_ocl_n$n"
    RATIOS="$RATIOS t2_cuda_e2e_n$n=t2_cpu_n$n/t2_cuda_n$n t2_ocl_e2e_n$n=t2_cpu_n$n/t2_ocl_n$n"
done
OCL_BIN=./genesis/src/nxgenesis_ocl
run_arms "$REPS" arm $ARMS; st=$?
campaign_done "$st" $RATIOS
exit $st
