#!/bin/sh
# Smoke test of the v2.6.2 release tarball on the laptop (Ubuntu 24.04, Radeon 890M).
B=/datadisk/od/nauka/1.Ac/0.Nauka/61.GENESIS/tmp-release-test-262
P=$B/genesis-v2.6.2-linux-x86_64
G=genesis/Scripts/benchmark/hh_spiking_benchmark.g
cd "$B/run" || exit 1
echo "checksums: $(cd $P && LC_ALL=C sha256sum -c SHA256SUMS | grep -vc ': OK$') failing"
sh genesis/Scripts/tests/run_tests.sh "$P/bin/nxgenesis_nocl" > tests.log 2>&1
echo "core tests exit $?: $(grep -c PASS tests.log) PASS, $(grep -vc PASS tests.log) other"
"$P/bin/nxgenesis_nocl" -nosimrc -notty -batch $G 500 2000 > cpu.log 2>&1
echo "cpu exit $?: $(grep VMFINAL cpu.log)"
ROCM=$(ls /etc/OpenCL/vendors/amdocl64*.icd | head -1)
OCL_ICD_VENDORS=$ROCM GENESIS_GPU_PRECISION=fp64 GENESIS_OCL_MULTILOOP=2010 "$P/bin/nxgenesis_ocl" -nosimrc -notty -batch $G 500 2000 > rocm.log 2>&1
echo "rocm fp64 exit $?: $(grep -E 'OCL: gotowy|nie znaleziono' rocm.log | head -1) | $(grep VMFINAL rocm.log)"
OCL_ICD_VENDORS=/etc/OpenCL/vendors/rusticl.icd RUSTICL_ENABLE=radeonsi GENESIS_OCL_MULTILOOP=2010 "$P/bin/nxgenesis_ocl" -nosimrc -notty -batch $G 500 2000 > rusticl.log 2>&1
echo "rusticl fp32 exit $?: $(grep -E 'OCL: gotowy|nie znaleziono' rusticl.log | head -1) | $(grep VMFINAL rusticl.log)"
