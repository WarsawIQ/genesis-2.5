#!/bin/bash
# NEURON 9.0.2 with CoreNEURON's GPU backend, built with NVHPC 24.11 -- as far
# as the CoreNEURON GPU arm of Table 5 needs it, and no further.
#
# What that arm needs is special-core and the nrnivmodl in this build tree:
# NEURON (the pip build, GCC) writes the model out with nrncore_write, and
# special-core reads it and simulates on the GPU without NEURON
# (../coreneuron/coreneuron_gpu_standalone.sh). The rest of an NVHPC-built
# NEURON does not work on this cluster, and nothing here uses it:
#
#   - both code generators, nocmodl and nmodl, segfault on every .mod file when
#     compiled by nvc++ (25.3 and 24.11 alike). They are host tools that emit
#     C++; the device code is compiled by nvc++ afterwards whoever built them.
#     So both are built with GCC first and put in the GPU tree before it needs
#     them.
#   - the NVHPC-built Python module segfaults on import, and nrniv on a single
#     passive soma. That is why the model is written out by the pip NEURON.
#
# `make install` is not run: it rewrites RPATHs and refuses the substituted
# generators, and the runs use this build tree directly, as the paper's did.
#
# Merged, in the order they were run, from as-found/build_gpu_24.sh,
# nocmodl_gcc_fix.sh, nmodl_gcc_fix.sh and resume_build.sh. The install step of
# finish_install.sh is left out for the reason above.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

TAG=9.0.2
REV=ba5783378c0aa1d9ac95b4454bea94b15c63f75d
GPU="$NRN_GPU_BUILD"
HOSTTOOLS="$NRN_GPU_SRC/build-hosttools"
HOSTNMODL="$NRN_GPU_SRC/build-hostnmodl"
NPROC=$(nproc)

if [ -x "$GPU/bin/nrnivmodl-core" ] && [ -x "$GPU/bin/nocmodl" ] \
   && "$GPU/bin/nmodl" --version >/dev/null 2>&1; then
    echo "NEURON GPU build already present in $GPU"
    exit 0
fi

[ -x "$MINIFORGE/bin/python3" ] || { echo "run 10_miniforge.sh first" >&2; exit 1; }
[ -x "$NVHPC_ROOT/compilers/bin/nvc++" ] || { echo "run 20_nvhpc.sh first" >&2; exit 1; }

# ---------------------------------------------------------------- source
if [ ! -d "$NRN_GPU_SRC/.git" ]; then
    git clone --depth 1 --branch "$TAG" https://github.com/neuronsimulator/nrn.git "$NRN_GPU_SRC"
fi
cd "$NRN_GPU_SRC"
[ "$(git rev-parse HEAD)" = "$REV" ] \
    || { echo "$NRN_GPU_SRC is not NEURON $TAG ($REV)" >&2; exit 1; }
git submodule update --init --recursive --depth 1

gcc_env() {
    export PATH="$GCC_TOOLSET/bin:$MINIFORGE/bin:$PATH"
    export LD_LIBRARY_PATH="$GCC_TOOLSET/lib64:${LD_LIBRARY_PATH:-}"
}

# ------------------------------------------- 1. nocmodl, built with GCC
(
    gcc_env
    rm -rf "$HOSTTOOLS"; mkdir -p "$HOSTTOOLS"; cd "$HOSTTOOLS"
    "$CMAKE" .. \
        -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
        -DNRN_ENABLE_PYTHON=OFF -DNRN_ENABLE_INTERVIEWS=OFF \
        -DNRN_ENABLE_RX3D=OFF -DNRN_ENABLE_MPI=OFF \
        -DNRN_ENABLE_CORENEURON=OFF -DCMAKE_BUILD_TYPE=Release > cmake.log 2>&1
    make -j"$NPROC" nocmodl > make.log 2>&1
)
NOCMODL="$HOSTTOOLS/bin/nocmodl"
[ -x "$NOCMODL" ] || { echo "no GCC nocmodl produced" >&2; exit 1; }
# A generator that fails here would fail identically in the GPU tree.
probe=$(mktemp -d "$SCRATCH/nocmodl_probe.XXXXXX")
printf 'NEURON { SUFFIX probe }\nASSIGNED { v }\n' > "$probe/probe.mod"
(cd "$probe" && "$NOCMODL" probe.mod >/dev/null 2>&1) \
    || { echo "GCC-built nocmodl fails too: the fault is not the compiler" >&2; exit 1; }
rm -rf "$probe"
echo "GCC nocmodl translates a .mod file"

# ------------------------------------------- 2. nmodl, built with GCC
(
    gcc_env
    rm -rf "$HOSTNMODL"; mkdir -p "$HOSTNMODL"; cd "$HOSTNMODL"
    "$CMAKE" .. \
        -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
        -DNRN_ENABLE_CORENEURON=ON -DCORENRN_ENABLE_GPU=OFF \
        -DNRN_ENABLE_INTERVIEWS=OFF -DNRN_ENABLE_RX3D=OFF -DNRN_ENABLE_MPI=OFF \
        -DNRN_ENABLE_PYTHON=ON -DPYTHON_EXECUTABLE="$MINIFORGE/bin/python3" \
        -DCMAKE_BUILD_TYPE=Release > cmake.log 2>&1
    make -j"$NPROC" nmodl > make.log 2>&1
)
NMODL="$HOSTNMODL/bin/nmodl"
"$NMODL" --version >/dev/null 2>&1 || { echo "GCC-built nmodl does not run" >&2; exit 1; }
echo "GCC nmodl runs"

# ------------------------------------------- 3. the GPU build, with NVHPC
export PATH="$MINIFORGE/bin:$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"
rm -rf "$GPU"; mkdir -p "$GPU"; cd "$GPU"
"$CMAKE" .. \
    -DCMAKE_C_COMPILER=nvc -DCMAKE_CXX_COMPILER=nvc++ \
    -DNRN_ENABLE_CORENEURON=ON -DCORENRN_ENABLE_GPU=ON \
    -DCMAKE_CUDA_ARCHITECTURES="80;86" \
    -DCMAKE_CUDA_COMPILER="$NVHPC_ROOT/cuda/12.6/bin/nvcc" \
    -DNRN_ENABLE_INTERVIEWS=OFF -DNRN_ENABLE_RX3D=OFF -DNRN_ENABLE_MPI=OFF \
    -DNRN_ENABLE_PYTHON=ON -DPYTHON_EXECUTABLE="$MINIFORGE/bin/python3" \
    -DCMAKE_BUILD_TYPE=Release > cmake.log 2>&1

# Let nvc++ build its own generators first, then overwrite them with the
# working GCC ones. Only then are they newer than every file they depend on,
# so make keeps them. Copying them in before the build does not work: their
# object files do not exist yet, so make relinks them with nvc++ and the build
# dies on the first .mod file (found by the fresh-prefix verification run of
# 2026-09-29). The paper's build got the same order by failing, substituting
# and resuming.
make -j"$NPROC" nocmodl nmodl > make.log 2>&1 \
    || { echo "could not build the generator targets; see $GPU/make.log" >&2; exit 1; }
cp -f "$NOCMODL" bin/nocmodl
cp -f "$NMODL" bin/nmodl

# The parallel build can lose a race on the generated nrnconf.h; a serial pass
# settles the generated headers, after which the parallel build completes.
make -j"$NPROC" >> make.log 2>&1 \
    || { make -j1 >> make.log 2>&1 && make -j"$NPROC" >> make.log 2>&1; } \
    || { echo "NEURON GPU build failed; see $GPU/make.log" >&2; exit 1; }

cmp -s "$GPU/bin/nocmodl" "$NOCMODL" && cmp -s "$GPU/bin/nmodl" "$NMODL" \
    || { echo "the build replaced a GCC generator; see the comment above" >&2; exit 1; }
[ -x "$GPU/bin/nrnivmodl-core" ] || { echo "no nrnivmodl-core in $GPU/bin" >&2; exit 1; }
echo "NEURON $TAG ($REV) with CoreNEURON GPU: $GPU"
