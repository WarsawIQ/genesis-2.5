#!/bin/sh
# E9: the OpenCL backend on non-NVIDIA hardware (reviewer point 7): the AMD
# Radeon 890M (gfx1150, integrated) under two independent OpenCL
# implementations, AMD ROCm and Mesa rusticl. Run on the laptop, on AC power,
# nothing else running. 3 replicates. ~60 min.
#
#   ap_*        correctness: hh1952_ap_verify.g, 8 neurons under one solver;
#               the neurons must agree, and RESULT_VM is compared with the CPU
#   t1_*        single-compartment network, N = 500, 5000, 50 000, K = 50 000
#   tr_*        dendritic trees N x 16, K = 5000, below the integrated-GPU cap
#               of 20 000 compartments
#   cap_*       2000 x 16 = 32 000 compartments with the cap in force: the
#               solver must say it falls back to the CPU, and the time shows it
#   *_rocm64    double precision under ROCm
#   ap_rusticl64  double precision under rusticl, which has none: must refuse
#
# Needs genesis/src/nxgenesis_ocl and nxgenesis_nocl built on the laptop
# (cluster_bringup/11_build_opencl.sh with the system's CL headers:
# OPENCL_CUDA_HOME pointing at any prefix whose include/ has CL/cl.h).
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-3}; T1N="500 5000 50000"; T1K=50000; TRN="100 300 1000"; TRK=5000
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && T1N=500 && T1K=5000 && TRN=100
ROCM_ICD=${ROCM_ICD:-$(ls /etc/OpenCL/vendors/amdocl64*.icd 2>/dev/null | head -1)}
RUSTICL_ICD=${RUSTICL_ICD:-/etc/OpenCL/vendors/rusticl.icd}
campaign_init E9
need genesis/src/nxgenesis_ocl "cluster_bringup/11_build_opencl.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/11_build_opencl.sh"
need "$ROCM_ICD" "ROCm OpenCL runtime"
need "$RUSTICL_ICD" "Mesa rusticl"
{ echo "# rocm_icd: $ROCM_ICD"; echo "# rusticl_icd: $RUSTICL_ICD"
  echo "# opencl: $(dpkg-query -W -f '${Package} ${Version}; ' rocm-opencl-runtime mesa-opencl-icd 2>/dev/null)"
  echo "# power: $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1) (1 = on AC)"; } >> "$CSV"
DEV='^OCL: urzadzenie: .*(gfx1150|Radeon)'

rt() {   # the environment that selects one OpenCL implementation
    case "$1" in
        rocm)    echo "OCL_ICD_VENDORS=$ROCM_ICD" ;;
        rusticl) echo "OCL_ICD_VENDORS=$RUSTICL_ICD RUSTICL_ENABLE=radeonsi" ;;
    esac
}
ap() {   # <arm> <rep> <order> <rocm|rusticl|cpu> <fp32|fp64> <banner>
    SANITY_RE='^NEURONS_AGREE: YES' SANITY_METRIC=agree
    if [ "$4" = cpu ]; then
        run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_grep \
            ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch genesis/Scripts/benchmark/hh1952_ap_verify.g 8 200
    else
        run_rep "$1" "$2" "$3" 0 "$6" sanity_grep \
            env $(rt "$4") GENESIS_GPU_PRECISION="$5" ./genesis/src/nxgenesis_ocl -nosimrc -notty \
            -batch genesis/Scripts/benchmark/hh1952_ap_verify.g 8 200
    fi
}
arm() {
    n=${1##*_n}; n=${n%%_*}
    case "$1" in
    ap_cpu)        ap "$1" "$2" "$3" cpu ;;
    ap_rocm32)     ap "$1" "$2" "$3" rocm fp32 "$DEV;$BANNER_OCL32" ;;
    ap_rocm64)     ap "$1" "$2" "$3" rocm fp64 "$DEV;$BANNER_OCL64" ;;
    ap_rusticl32)  ap "$1" "$2" "$3" rusticl fp32 "$DEV;$BANNER_OCL32" ;;
    ap_rusticl64)  ap "$1" "$2" "$3" rusticl fp64 'has no double-precision support.*Computing on the CPU' ;;
    t1_cpu_n*)     EXPECT_N=$n EXPECT_STEPS=$T1K
                   run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_single \
                       ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch genesis/Scripts/benchmark/hh_spiking_benchmark.g "$n" "$T1K" ;;
    t1_*_n*)       r=${1#t1_}; r=${r%%_*}; EXPECT_N=$n EXPECT_STEPS=$T1K
                   run_rep "$1" "$2" "$3" 0 "$DEV;$BANNER_OCL32" sanity_single \
                       env $(rt "$r") GENESIS_OCL_MULTILOOP="$T1K" ./genesis/src/nxgenesis_ocl -nosimrc -notty \
                       -batch genesis/Scripts/benchmark/hh_spiking_benchmark.g "$n" "$T1K" ;;
    tr_cpu_n*)     tree_rep "$1" "$2" "$3" cpu "$n" "$TRK" 16 ;;
    tr_rocm64_n*)  tree_rep "$1" "$2" "$3" ocl64 "$n" "$TRK" 16 $(rt rocm) ;;
    tr_*_n*)       r=${1#tr_}; r=${r%%_*}; tree_rep "$1" "$2" "$3" ocl32 "$n" "$TRK" 16 $(rt "$r") ;;
    cap_cpu)       tree_rep "$1" "$2" "$3" cpu 2000 "$TRK" 16 ;;
    cap_*)         r=${1#cap_}; EXPECT_N=2000 EXPECT_STEPS=$TRK EXPECT_NCOMP=16
                   run_rep "$1" "$2" "$3" 0 'exceeds the safe cap.*Falling back to CPU' sanity_tree \
                       env $(rt "$r") GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 \
                       GENESIS_OCL_MULTILOOP=$((TRK + 10)) ./genesis/src/nxgenesis_ocl -nosimrc -notty \
                       -batch genesis/Scripts/benchmark/hh_multicompartment_createmap.g 2000 "$TRK" ;;
    esac
}
OCL_BIN=./genesis/src/nxgenesis_ocl
ARMS="ap_cpu ap_rocm32 ap_rocm64 ap_rusticl32 ap_rusticl64"; RATIOS=""
for n in $T1N; do
    ARMS="$ARMS t1_cpu_n$n t1_rocm_n$n t1_rusticl_n$n"
    RATIOS="$RATIOS t1_rocm_n$n=t1_cpu_n$n/t1_rocm_n$n t1_rusticl_n$n=t1_cpu_n$n/t1_rusticl_n$n"
done
for n in $TRN; do
    ARMS="$ARMS tr_cpu_n$n tr_rocm_n$n tr_rusticl_n$n tr_rocm64_n$n"
    RATIOS="$RATIOS tr_rocm_n$n=tr_cpu_n$n/tr_rocm_n$n tr_rusticl_n$n=tr_cpu_n$n/tr_rusticl_n$n tr_rocm_fp64_cost_n$n=tr_rocm64_n$n/tr_rocm_n$n"
done
[ "$CAMPAIGN_DRY" = 1 ] || ARMS="$ARMS cap_cpu cap_rocm cap_rusticl"
run_arms "$REPS" arm $ARMS; st=$?
# RESULT_VM of every correctness run against the CPU's, for the report
for f in "$RUNS"/ap_*_r1.log; do
    printf '%s %s\n' "$(basename "$f" _r1.log)" "$(sed -n 's/^RESULT_VM= *//p' "$f" | head -1)"
done | tee "$RUNS/notes"
campaign_done "$st" $RATIOS
exit $st
