#!/bin/bash
# Build the transcribed COBAHH channels (mechanisms/khh.mod, nahh.mod) for the
# NEURON and CoreNEURON arms of Table 5.
#
# The benchmark as published defines its channels with ChannelBuilder, inside
# the NEURON interpreter, which CoreNEURON does not have (see README.md). The
# NMODL transcriptions in mechanisms/ are copied into the ModelDB model and
# compiled twice:
#
#   cpu  $COBAHH_DIR/x86_64       pip NEURON (GCC), for the NEURON and
#                                 CoreNEURON CPU arms and for writing the model
#                                 out for the GPU arm
#   gpu  $COBAHH_GPU_MECH/x86_64  the NVHPC build tree, for special-core on the
#                                 GPU. Linked with -lstdc++fs: without it
#                                 special-core fails to load with an undefined
#                                 std::filesystem symbol, because neither the
#                                 system nor the gcc-toolset-13 libstdc++.so
#                                 exports it and libstdc++fs is static only.
#
# From as-found/build_cn.sh (cpu) and the command recorded in the paper build's
# x86_64_gpu2/b.log (gpu).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

WHICH=${1:-both}
[ -f "$COBAHH_DIR/init.hoc" ] || { echo "run toolchains/fetch_modeldb_83319.sh first" >&2; exit 1; }
mkdir -p "$COBAHH_DIR/mechanisms"
cp -f "$ROOT/cluster_bringup/coreneuron/mechanisms/"*.mod "$COBAHH_DIR/mechanisms/"

if [ "$WHICH" = cpu ] || [ "$WHICH" = both ]; then
    cd "$COBAHH_DIR"
    rm -rf x86_64
    PATH="$NRN_PIP_BIN:$PATH" nrnivmodl -coreneuron mechanisms > build_cpu.log 2>&1 \
        || { echo "CPU mechanism build failed; see $COBAHH_DIR/build_cpu.log" >&2; exit 1; }
    ls x86_64/libcorenrnmech.so x86_64/libnrnmech.so
fi

if [ "$WHICH" = gpu ] || [ "$WHICH" = both ]; then
    [ -x "$NRN_GPU_BUILD/bin/nrnivmodl" ] || { echo "run toolchains/30_neuron_gpu.sh first" >&2; exit 1; }
    rm -rf "$COBAHH_GPU_MECH"; mkdir -p "$COBAHH_GPU_MECH"; cd "$COBAHH_GPU_MECH"
    PATH="$NVHPC_ROOT/compilers/bin:$PATH" \
    LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}" \
        "$NRN_GPU_BUILD/bin/nrnivmodl" -coreneuron -loadflags -lstdc++fs ../mechanisms > b.log 2>&1 \
        || { echo "GPU mechanism build failed; see $COBAHH_GPU_MECH/b.log" >&2; exit 1; }
    [ -x x86_64/special-core ] || { echo "no special-core produced" >&2; exit 1; }
    ls x86_64/special-core
fi
