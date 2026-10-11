#!/bin/sh
# What a machine of the campaign runs: OS, kernel, compiler, C library, GPU
# driver and runtimes, for the paper's "Computing platforms" entry.
#
#     sh cluster_bringup/campaign/platform_info.sh
#
# Writes logs/campaign_prep/platform_<host>.txt. Reads only; needs nothing
# beyond the tools it finds.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/platform_$(hostname -s).txt
mkdir -p "$(dirname "$OUT")"
{
echo "# host $(hostname -s), $(date -Is)"
echo "os: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo "kernel: $(uname -r) $(uname -m)"
echo "cpu: $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
echo "glibc: $(ldd --version 2>/dev/null | head -1)"
echo "gcc: $(gcc --version 2>/dev/null | head -1)"
command -v nvidia-smi >/dev/null && echo "nvidia: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"
for c in /usr/local/cuda/bin/nvcc "${CUDA_HOME:-/nonexistent}/bin/nvcc"; do
    [ -x "$c" ] && echo "nvcc: $($c --version | tail -1)" && break
done
command -v dpkg-query >/dev/null && echo "opencl packages: $(dpkg-query -W -f '${Package} ${Version}; ' rocm-opencl-runtime mesa-opencl-icd ocl-icd-libopencl1 2>/dev/null)"
command -v clinfo >/dev/null && echo "opencl platforms: $(clinfo -l 2>/dev/null | tr -s ' ' | tr '\n' ';')"
command -v python3 >/dev/null && echo "python3: $(python3 --version 2>&1)"
} > "$OUT"
cat "$OUT"
echo "written: $OUT"
