#!/bin/bash
# Arbor 0.10.0 with CUDA, for every Arbor arm in the paper (CPU and GPU).
#
# The pip wheel has no GPU support (arbor.config()["gpu"] is None), so this is
# a source build. It is pinned to v0.10.0 for a reason, not by accident: Arbor
# 0.12 needs CMake >= 4.0 but still calls find_package(CUDA), which CMake 4.0
# removed, so the two cannot both be satisfied. 0.10.0 builds with the system
# CMake 3.26, which still has it.
#
# The CPU target is pinned too. Arbor defaults to -march=native, and the
# paper's build was made on a GPU node (Ice Lake, AVX-512): it runs on inf02 and
# inf03 and dies with "Illegal instruction" on the Haswell login node. Built
# natively on the login node instead, it would run everywhere but lose the
# AVX-512 paths, which would move the Arbor CPU arm of Table 7. ARB_ARCH makes
# the result independent of where the recipe happens to run.
#
# From as-found/build_arbor_gpu.sh. That script fell back to the default branch
# if the tag could not be cloned; this one refuses instead, since a different
# Arbor would silently change the comparison.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

TAG=v0.10.0
REV=6b6cc900b85fbf833fae94817b9406a0d690dc28
SRC="$WORK_DIR/arbor_src"
B="$SRC/build"

check() {
    PYTHONPATH="$ARBOR_PY" LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
        "$ARBOR_PYTHON" -c 'import arbor; import sys
v, g = arbor.__version__, arbor.config()["gpu"]
print("arbor", v, "gpu", g)
sys.exit(0 if (v, g) == ("0.10.0", "cuda") else 1)'
}

# A build for Ice Lake cannot be imported on an older CPU, such as the login
# node's. There, the recipe builds and installs but leaves the import check to
# ../coreneuron/arbor_check.sh on a GPU node.
can_run() { [ "$ARB_ARCH" != icelake-server ] || grep -q avx512f /proc/cpuinfo; }

if [ -d "$ARBOR_PY/arbor" ]; then
    if ! can_run; then
        echo "Arbor installed in $ARBOR_PREFIX; check it on a GPU node with coreneuron/arbor_check.sh"
        exit 0
    elif check 2>/dev/null; then
        echo "Arbor $TAG with CUDA already installed in $ARBOR_PREFIX"
        exit 0
    fi
fi
[ -x "$ARBOR_PYTHON" ] || { echo "run 10_miniforge.sh first" >&2; exit 1; }

export PATH="$GCC_TOOLSET/bin:$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$GCC_TOOLSET/lib64:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

[ -d "$SRC/.git" ] || git clone --depth 1 --branch "$TAG" https://github.com/arbor-sim/arbor.git "$SRC"
cd "$SRC"
[ "$(git rev-parse HEAD)" = "$REV" ] || { echo "$SRC is not Arbor $TAG ($REV)" >&2; exit 1; }
git submodule update --init --recursive --depth 1

rm -rf "$B"; mkdir -p "$B"; cd "$B"
# A40 is sm_86 and A100 sm_80; build for both.
"$CMAKE" .. \
    -DCMAKE_INSTALL_PREFIX="$ARBOR_PREFIX" \
    -DARB_GPU=cuda \
    -DARB_ARCH="$ARB_ARCH" \
    -DCMAKE_CUDA_ARCHITECTURES="80;86" \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -DCUDAToolkit_ROOT="$CUDA_HOME" \
    -DCUDA_TOOLKIT_ROOT_DIR="$CUDA_HOME" \
    -DARB_WITH_PYTHON=ON \
    -DPython3_EXECUTABLE="$ARBOR_PYTHON" \
    -DPython3_ROOT_DIR="$MINIFORGE" \
    -DARB_USE_BUNDLED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release > cmake.log 2>&1
make -j"$(nproc)" > make.log 2>&1 || { echo "Arbor build failed; see $B/make.log" >&2; exit 1; }
make install > install.log 2>&1

if can_run; then
    check
else
    echo "Arbor $TAG built for $ARB_ARCH and installed in $ARBOR_PREFIX."
    echo "This machine cannot run that code; check it on a GPU node:"
    echo "    sh cluster_bringup/coreneuron/arbor_check.sh"
fi
