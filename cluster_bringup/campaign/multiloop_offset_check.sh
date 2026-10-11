#!/bin/sh
# Does the single-compartment multiloop compute what the CPU does?
#
#     sh cluster_bringup/campaign/multiloop_offset_check.sh <release checkout>
#
# hh_spiking_benchmark.g (Table 1, E9's t1 arms) does `reset`, `step 10` (a
# warm-up) and `step N`. A multiloop of K steps runs all K at the first solver
# call, i.e. in the first warm-up step, and turns every later call into a
# no-op; so with K = N, as E3 and E9 set it, the GPU runs N steps where the CPU
# runs N + 10, and the final voltages differ (the script's comment blamed fp32
# for that). This runs the CPU binary and the OpenCL binary in fp64, with
# K = N and with K = N + 10, for N = 1, 200, 2000, and records the final
# voltage of each: with K = N + 10 it must equal the CPU's to every digit.
# OPENCL_VENDORS picks the ICD (default: the first ROCm one).
#
# Writes logs/campaign_prep/multiloop_offset_<host>_<time>.csv.
set -u
[ $# -eq 1 ] || { echo "usage: $0 <release checkout>" >&2; exit 2; }
REL=$(cd "$1" && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
ICD=${OPENCL_VENDORS:-$(ls /etc/OpenCL/vendors/amdocl64*.icd 2>/dev/null | head -1)}
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/multiloop_offset_$(hostname -s)_$(date +%Y%m%d_%H%M%S).csv
mkdir -p "$(dirname "$OUT")"
G=genesis/Scripts/benchmark/hh_spiking_benchmark.g
cd "$REL" || exit 2
v() { "$@" 2>&1 | sed -n 's/^VMFINAL 0 *//p' | tr -d ' '; }
{
echo "# host $(hostname -s); binaries $(git describe --tags --always) nxgenesis_ocl sha256 $(sha256sum genesis/src/nxgenesis_ocl | cut -d' ' -f1); ICD $ICD; fp64; 500 cells"
echo "n_steps,cpu_vm,ocl_K_eq_N_vm,ocl_K_eq_N_plus_10_vm,equal_with_plus_10"
} > "$OUT"
for n in 1 200 2000; do
    c=$(v ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch $G 500 $n)
    a=$(OCL_ICD_VENDORS=$ICD GENESIS_GPU_PRECISION=fp64 GENESIS_OCL_MULTILOOP=$n v ./genesis/src/nxgenesis_ocl -nosimrc -notty -batch $G 500 $n)
    b=$(OCL_ICD_VENDORS=$ICD GENESIS_GPU_PRECISION=fp64 GENESIS_OCL_MULTILOOP=$((n + 10)) v ./genesis/src/nxgenesis_ocl -nosimrc -notty -batch $G 500 $n)
    eq=no; [ -n "$c" ] && [ "$c" = "$b" ] && eq=yes
    echo "$n,$c,$a,$b,$eq" | tee -a "$OUT"
done
echo "written: $OUT"
