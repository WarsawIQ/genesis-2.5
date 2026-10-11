#!/bin/sh
# The binary tarball attached to a GitHub release.
#
#     sh cluster_bringup/campaign/package_release.sh <release checkout> <version> [<measured tag>]
#
# Packs the three binaries of <release checkout> (built there by
# prepare_node.sh: nxgenesis with CUDA, nxgenesis_ocl with OpenCL,
# nxgenesis_nocl for the CPU) with genesis/startup into
# genesis-<version>-linux-x86_64.tar.gz. If <measured tag> is given, the
# checkout must be at that tag and its binaries must match the sha256 recorded
# by that tag's campaign build on this node, so the tarball holds the very
# binaries the paper was measured with. The tarball's README.txt records where
# they come from, the libraries they need (ldd) and the GPU architectures the
# CUDA binary carries (cuobjdump).
#
# Writes the tarball and its manifest to logs/release/<version>/ under this
# script's repository; commit the manifest, attach the tarball to the release.
set -u
[ $# -ge 2 ] || { echo "usage: $0 <release checkout> <version> [<measured tag>]" >&2; exit 2; }
REL=$(cd "$1" && pwd); VER=$2; MEAS=${3:-}
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
OUT=$GENESIS_ROOT/cluster_bringup/logs/release/$VER
NAME=genesis-$VER-linux-x86_64
mkdir -p "$OUT"
cd "$REL" || exit 2
if [ -n "$MEAS" ]; then
    [ "$(git describe --tags --exact-match 2>/dev/null)" = "$MEAS" ] \
        || { echo "REFUSED: $REL is not at $MEAS" >&2; exit 1; }
    REC=cluster_bringup/logs/campaign_$MEAS/build_$(hostname -s)/binaries.sha256
    [ -f "$REC" ] || { echo "REFUSED: no $REC" >&2; exit 1; }
    for b in nxgenesis nxgenesis_ocl nxgenesis_nocl; do
        want=$(awk -v b="$b" '$2 == b || $2 ~ "/"b"$" { print $1 }' "$REC" | head -1)
        have=$(sha256sum "genesis/src/$b" | cut -d' ' -f1)
        [ -n "$want" ] && [ "$want" = "$have" ] \
            || { echo "REFUSED: genesis/src/$b is not the binary $REC records" >&2; exit 1; }
    done
fi
T=$(mktemp -d); P=$T/$NAME
mkdir -p "$P/bin/hines/opencl" "$P/startup"
cp genesis/src/nxgenesis genesis/src/nxgenesis_ocl genesis/src/nxgenesis_nocl "$P/bin/"
# the OpenCL backend compiles this at run time and looks for it next to the binary
cp genesis/src/hines/opencl/ocl_channel.cl "$P/bin/hines/opencl/"
cp -r genesis/startup/. "$P/startup/"
NVCC=${CUDA_HOME:-/nonexistent}/bin
{
echo "GENESIS $VER, Linux x86_64 binaries"
echo
echo "Built from $(git describe --tags --always) ($(git rev-parse HEAD)) on $(hostname -s),"
echo "$(. /etc/os-release && echo "$PRETTY_NAME"), $(ldd --version | head -1), $(gcc --version | head -1)."
[ -n "$MEAS" ] && echo "These are the binaries every number of the SoftwareX paper was measured with ($MEAS);"
[ -n "$MEAS" ] && echo "the GENESIS sources of $VER are identical to those of $MEAS."
echo
echo "bin/nxgenesis_nocl  CPU only; needs glibc and ncurses."
echo "bin/nxgenesis_ocl   OpenCL 1.2 (any vendor's ICD, e.g. ROCm, Mesa rusticl, NVIDIA). It compiles"
echo "                    bin/hines/opencl/ocl_channel.cl at run time and finds it next to itself;"
echo "                    keep the two together or name the file in GENESIS_OCL_KERNEL. Without it"
echo "                    the backend says 'nie znaleziono ocl_channel.cl' and computes on the CPU."
cudalibs="the NVIDIA driver and the CUDA 12 runtime (libcudart.so.12)"
ldd genesis/src/nxgenesis | grep -q libOpenCL && cudalibs="$cudalibs, and an OpenCL ICD loader (libOpenCL.so.1)"
echo "bin/nxgenesis       CUDA; needs $cudalibs."
if [ -x "$NVCC/cuobjdump" ]; then
    sass=$("$NVCC/cuobjdump" --list-elf genesis/src/nxgenesis 2>/dev/null | sed -n 's/.*\.\(sm_[0-9]*\)\.cubin.*/\1/p' | sort -u | tr '\n' ' ')
    ptx=$("$NVCC/cuobjdump" --list-ptx genesis/src/nxgenesis 2>/dev/null | sed -n 's/.*\.\(sm_[0-9]*\)\.ptx.*/\1/p' | sort -u | tr '\n' ' ')
    echo "                    GPU code: native for ${sass:-none}; PTX for ${ptx:-none}, which the driver"
    echo "                    compiles for newer GPUs. GPUs older than the lowest of these do not run it."
fi
echo
echo "Run from a directory holding a .simrc that puts startup/ on SIMPATH, as genesis/startup"
echo "is used in a source build (see README.md of the repository), e.g."
echo "    setenv SIMPATH . <this directory>/startup"
echo "Choose precision and batching at run time: GENESIS_GPU_PRECISION=fp32|fp64,"
echo "GENESIS_CUDA_MULTILOOP=<K>, GENESIS_OCL_MULTILOOP=<K>. Known issues: KNOWN_ISSUES.md"
echo "in the repository."
echo
for b in nxgenesis_nocl nxgenesis_ocl nxgenesis; do
    echo "== ldd $b"; ldd "genesis/src/$b" | sed 's/ (0x[0-9a-f]*)//'
done
if [ -x "$NVCC/cuobjdump" ]; then
    echo "== GPU code in nxgenesis (cuobjdump --list-elf --list-ptx)"
    "$NVCC/cuobjdump" --list-elf --list-ptx genesis/src/nxgenesis 2>&1
fi
} > "$P/README.txt"
( cd "$P" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + | sort -k2 > SHA256SUMS )
tar -C "$T" -czf "$OUT/$NAME.tar.gz" "$NAME"
# Smoke test of the tarball as a user gets it: unpacked elsewhere, the OpenCL
# binary must find its kernel and start on the device (when there is one).
S=$(mktemp -d); mkdir -p "$S/run/genesis/src" "$S/run/genesis/Scripts/benchmark"
tar -C "$S" -xzf "$OUT/$NAME.tar.gz"
ln -s "$S/$NAME/startup" "$S/run/genesis/src/startup"
cp genesis/Scripts/benchmark/hh_spiking_benchmark.g "$S/run/genesis/Scripts/benchmark/"
( cd "$S/run" && GENESIS_OCL_MULTILOOP=210 "$S/$NAME/bin/nxgenesis_ocl" -nosimrc -notty -batch \
      genesis/Scripts/benchmark/hh_spiking_benchmark.g 100 200 > smoke.log 2>&1 )
if grep -q "nie znaleziono ocl_channel.cl" "$S/run/smoke.log"; then
    echo "REFUSED: the packaged OpenCL binary does not find its kernel" >&2; rm -rf "$S" "$T"; exit 1
fi
smoke=$(grep -m1 "^OCL: gotowy" "$S/run/smoke.log" || echo "no OpenCL device here; kernel found")
rm -rf "$S"
{
echo "# $NAME.tar.gz, $(date -Is)"
sha256sum "$OUT/$NAME.tar.gz" | sed "s|$OUT/||"
echo
cat "$P/README.txt"
echo
echo "== smoke test (unpacked elsewhere, nxgenesis_ocl, 100 cells): $smoke"
echo
echo "== SHA256SUMS"
cat "$P/SHA256SUMS"
} > "$OUT/manifest.txt"
rm -rf "$T"
cat "$OUT/manifest.txt" | head -40
echo "written: $OUT"
