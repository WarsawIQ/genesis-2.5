#!/bin/bash
# Build Arbor with CUDA.
#
# Reviewer 2 asked for a comparison against "CoreNEURON or Arbor". CoreNEURON's
# GPU path is unreachable on this cluster: it offloads through OpenACC, needs
# NVIDIA's compilers, and every NEURON binary those compilers produce segfaults.
# Arbor targets CUDA directly, so it needs only the toolkit already installed
# here and an ordinary C++ compiler -- none of that blocker applies.
#
# The pip wheel reports config()["gpu"] = None, so GPU requires this source build.
set -eu
[ -d /opt/rh/gcc-toolset-13/root/usr/bin ] && {
    export PATH="/opt/rh/gcc-toolset-13/root/usr/bin:$PATH"
    export LD_LIBRARY_PATH="/opt/rh/gcc-toolset-13/root/usr/lib64:${LD_LIBRARY_PATH:-}"
}
CUDA=/storage/opt/cuda/cuda-12.8
export PATH="$CUDA/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA/lib64:${LD_LIBRARY_PATH:-}"
# Arbor v0.12 needs CMake >= 4.0; the cluster has 3.26.5. pip ships current
# CMake binaries, so this needs no administrator.
# Arbor v0.12 requires CMake >= 4.0 yet still calls find_package(CUDA), a module
# CMake 4.0 removed -- the two cannot both be satisfied. v0.10.0 builds against
# the system CMake 3.26, which still provides it.
echo "cmake: $(cmake --version | head -1)"
echo "g++: $(g++ --version | head -1)"
echo "nvcc: $(nvcc --version | tail -2 | head -1)"

SRC="$HOME/arbor_src"; B="$SRC/build"; P="$HOME/opt/arbor-gpu"
[ -d "$SRC/.git" ] || git clone --depth 1 --branch v0.10.0 \
    https://github.com/arbor-sim/arbor.git "$SRC" 2>/dev/null \
    || git clone --depth 1 https://github.com/arbor-sim/arbor.git "$SRC"
cd "$SRC" && git submodule update --init --recursive --depth 1 >/dev/null 2>&1 || true

rm -rf "$B"; mkdir -p "$B"; cd "$B"
CMAKE=/usr/bin/cmake
echo "using $($CMAKE --version | head -1)"
# A40 is sm_86 and A100 sm_80; build for both.
"$CMAKE" .. \
    -DCMAKE_INSTALL_PREFIX="$P" \
    -DARB_GPU=cuda \
    -DCMAKE_CUDA_ARCHITECTURES="80;86" \
    -DCMAKE_CUDA_COMPILER="$CUDA/bin/nvcc" \
    -DCUDAToolkit_ROOT="$CUDA" \
    -DCUDA_TOOLKIT_ROOT_DIR="$CUDA" \
    -DARB_WITH_PYTHON=ON \
    -DPython3_EXECUTABLE="$HOME/opt/miniforge/bin/python3" \
    -DPython3_ROOT_DIR="$HOME/opt/miniforge" \
    -DARB_USE_BUNDLED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    > cmake.log 2>&1 || { echo "CMAKE FAILED"; grep -iE "error|could not" cmake.log | head -12; exit 1; }
echo "cmake ok; building on $(nproc) cores ..."
make -j"$(nproc)" > make.log 2>&1 || { echo "BUILD FAILED"; grep -iE " error" make.log | head -15; exit 1; }
make install > install.log 2>&1 || true
echo "=== done ==="
find "$P" -name "*.so" 2>/dev/null | head -3
