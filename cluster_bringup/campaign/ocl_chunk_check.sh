#!/bin/sh
# The OpenCL single-compartment multiloop in pieces (2.6.1): same result, no reset.
#
#     sh cluster_bringup/campaign/ocl_chunk_check.sh [<checkout with binaries>]
#
# On an integrated GPU 2.6.1 runs a multiloop in dispatches of about
# GENESIS_OCL_DISPATCH_MS (500 ms by default) instead of one, because one long
# dispatch tripped the driver's lockup timeout under Mesa rusticl (E9 on
# v2.6.0-rc4, KNOWN_ISSUES.md). The pieces must not change the result. This
# runs hh_spiking_benchmark.g (K = N + 10, so the GPU runs the steps the CPU
# runs) for 500 cells (one piece: the first, short piece covers the run) and
# for 50 000 cells over 2000 steps (many pieces, while one dispatch is still
# safe) on the CPU and under each OpenCL runtime found, with one dispatch
# (GENESIS_OCL_DISPATCH_MS=0), the default and tiny pieces
# (GENESIS_OCL_DISPATCH_MS=1), and checks:
#   - fp64: every variant prints the CPU's final voltage to every digit (a
#     runtime without double precision must refuse and compute on the CPU);
#   - fp32: the three variants print the same voltage;
# then runs E9's case that was reset (50 000 cells, 50 000 steps) under
# rusticl with the default pieces and checks the kernel log for ring timeouts.
#
# Writes logs/campaign_prep/ocl_chunk_check_<host>_<time>.txt. Exit 0 when all
# checks pass.
set -u
REL=$(cd "${1:-$(dirname "$0")/../..}" && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/ocl_chunk_check_$(hostname -s)_$(date +%Y%m%d_%H%M%S).txt
mkdir -p "$(dirname "$OUT")"
G=genesis/Scripts/benchmark/hh_spiking_benchmark.g
ROCM=$(ls /etc/OpenCL/vendors/amdocl64*.icd 2>/dev/null | head -1)
RUSTICL=/etc/OpenCL/vendors/rusticl.icd
cd "$REL" || exit 2
fail=0
vm() { sed -n 's/^VMFINAL 0 *//p' "$1" | tr -d ' '; }
ocl() {   # icd precision dispatch_ms n steps log
    env OCL_ICD_VENDORS="$1" RUSTICL_ENABLE=radeonsi GENESIS_GPU_PRECISION="$2" \
        GENESIS_OCL_DISPATCH_MS="$3" GENESIS_OCL_MULTILOOP=$(($5 + 10)) \
        ./genesis/src/nxgenesis_ocl -nosimrc -notty -batch $G "$4" "$5" > "$6" 2>&1
}
{
echo "# $(hostname -s), $(git describe --tags --always --dirty) $(git rev-parse HEAD)"
echo "# nxgenesis_ocl sha256 $(sha256sum genesis/src/nxgenesis_ocl | cut -d' ' -f1)"
T=$(mktemp -d)
for case in 500:200 500:2000 50000:2000; do
    C=${case%:*}; N=${case#*:}
    ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch $G $C $N > "$T/cpu.log" 2>&1
    cpu=$(vm "$T/cpu.log")
    echo "== $C cells, N=$N: cpu $cpu"
    for rt in rocm rusticl; do
        icd=$ROCM; [ $rt = rusticl ] && icd=$RUSTICL
        [ -f "$icd" ] || { echo "   $rt: no ICD, skipped"; continue; }
        for p in fp64 fp32; do
            line="   $rt $p:"
            for ms in 0 default 1; do
                d=$ms; [ $ms = default ] && d=""
                if [ -n "$d" ]; then ocl "$icd" $p "$d" $C $N "$T/o.log"
                else env -u GENESIS_OCL_DISPATCH_MS OCL_ICD_VENDORS="$icd" RUSTICL_ENABLE=radeonsi GENESIS_GPU_PRECISION=$p \
                         GENESIS_OCL_MULTILOOP=$((N + 10)) ./genesis/src/nxgenesis_ocl -nosimrc -notty \
                         -batch $G $C $N > "$T/o.log" 2>&1; fi
                v=$(vm "$T/o.log")
                if ! grep -q "kernele $p" "$T/o.log"; then
                    if [ $p = fp64 ] && grep -q "has no double-precision support" "$T/o.log"; then
                        v="$v(refused,cpu)"
                    else v="NOT-ON-GPU"; fi
                fi
                np=$(sed -n 's/^OCL MULTILOOP: \([0-9]*\) dispatches.*/\1/p' "$T/o.log"); np=${np:-1}
                line="$line ms=$ms -> $v ($np)"
                eval "v_$ms=\$v"
            done
            echo "$line"
            if [ $p = fp64 ]; then
                for x in "$v_0" "$v_default" "$v_1"; do [ "${x%(refused,cpu)}" = "$cpu" ] || { echo "   FAIL: fp64 differs from the CPU"; fail=1; break; }; done
            elif [ "$v_0" != "$v_default" ] || [ "$v_0" != "$v_1" ]; then
                echo "   FAIL: fp32 pieces differ from one dispatch"; fail=1
            fi
        done
    done
done
if [ -f "$RUSTICL" ]; then
    since=$(date '+%Y-%m-%d %H:%M:%S')
    t0=$(date +%s%N)
    env OCL_ICD_VENDORS="$RUSTICL" RUSTICL_ENABLE=radeonsi GENESIS_GPU_PRECISION=fp32 \
        GENESIS_OCL_MULTILOOP=50010 ./genesis/src/nxgenesis_ocl -nosimrc -notty -batch $G 50000 50000 \
        > "$T/big.log" 2>&1
    rc=$?
    t1=$(date +%s%N)
    resets=$(journalctl -k --since "$since" --no-pager 2>/dev/null | grep -ci 'amdgpu.*\(ring .* timeout\|reset\|wedged\)')
    echo "== rusticl, 50000 cells x 50000 steps, default pieces: exit $rc, wall $(awk "BEGIN{printf \"%.1f\", ($t1-$t0)/1e9}") s, $(grep '^OCL MULTILOOP: [0-9]* dispatches' "$T/big.log"), kernel-log resets: $resets"
    [ "$rc" = 0 ] && [ "$resets" = 0 ] || { echo "   FAIL: the large run did not complete cleanly"; fail=1; }
fi
rm -rf "$T"
echo "result: $([ $fail = 0 ] && echo PASS || echo FAIL)"
} 2>&1 | tee "$OUT"
echo "written: $OUT"
grep -q "^result: PASS" "$OUT"
