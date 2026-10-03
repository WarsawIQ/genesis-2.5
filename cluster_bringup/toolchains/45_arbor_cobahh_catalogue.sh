#!/bin/sh
# The COBAHH sodium and potassium channels compiled into an Arbor catalogue with
# CUDA, for the Arbor arm of the spiking-network comparison
# (cluster_bringup/arbor_vanet2/vanet2_arbor.py reads it from ARBOR_COBAHH_CAT).
#
# The channels are cluster_bringup/arbor_vanet2/mech/, the NMODL transcriptions
# of the benchmark's ChannelBuilder channels with the two edits Arbor's modcc
# needs (see arbor_vanet2/README.md). Needs 40_arbor_gpu.sh. Run on a GPU node:
# the build is checked by loading the catalogue.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"
OUT=$(dirname "$ARBOR_COBAHH_CAT")
export PATH="$ARBOR_PREFIX/bin:$GCC_TOOLSET/bin:$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$GCC_TOOLSET/lib64:$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$ARBOR_PY"

check() {
    "$ARBOR_PYTHON" -c 'import arbor, sys
cat = arbor.load_catalogue(sys.argv[1])
names = sorted(cat.keys())
print("catalogue", sys.argv[1], "mechanisms", names)
sys.exit(0 if names else 1)' "$ARBOR_COBAHH_CAT"
}

can_run() { [ "$ARB_ARCH" != icelake-server ] || grep -q avx512f /proc/cpuinfo; }
can_run || { echo "this CPU cannot run the $ARB_ARCH Arbor build; run on a GPU node" >&2; exit 1; }
if [ -f "$ARBOR_COBAHH_CAT" ] && [ -f "$OUT/.recipe_ok" ] && check 2>/dev/null; then
    echo "catalogue already built: $ARBOR_COBAHH_CAT"
    exit 0
fi
T="$ARBOR_PREFIX/lib64/cmake/arbor/arbor-targets.cmake"
if [ ! -e /usr/lib64/libhwloc.so ] && grep -q '/usr/lib64/libhwloc\.so[";]' "$T" 2>/dev/null; then
    so=$(ls /usr/lib64/libhwloc.so.[0-9]* 2>/dev/null | head -1)
    [ -n "$so" ] || { echo "no libhwloc on this node" >&2; exit 1; }
    sed -i "s|/usr/lib64/libhwloc\.so\([\";]\)|$so\1|g" "$T"
    echo "pointed $T at $so"
fi
ABC="$ARBOR_PREFIX/bin/arbor-build-catalogue"
[ -f "$ABC" ] || { echo "no $ABC; run 40_arbor_gpu.sh" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"
cp -r "$ROOT/cluster_bringup/arbor_vanet2/mech" "$OUT/mech"
cd "$OUT"
# Through ARBOR_PYTHON: the script's "#!/usr/bin/env python3" finds the
# system Python 3.6 on the cluster, which cannot import this Arbor.
"$ARBOR_PYTHON" "$ABC" cobahh mech --gpu cuda
check
sha256sum "$ROOT"/cluster_bringup/arbor_vanet2/mech/* > "$OUT/.recipe_ok"
echo "built $ARBOR_COBAHH_CAT"
