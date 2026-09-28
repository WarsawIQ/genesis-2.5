#!/bin/bash
# NEURON's GPU build needs Python development headers, and the cluster has none
# for either python3.6 or python3.12 (/usr/include/python3.12 exists but holds no
# Python.h). Rather than building without Python, install a self-contained Python
# that ships its headers: the CPU arm of this comparison was driven through the
# Python API, and keeping the same driver keeps the two measurements comparable.
set -eu

MF="$HOME/opt/miniforge"
if [ ! -x "$MF/bin/python3" ]; then
    cd "$HOME"
    curl -sSL --retry 3 -o miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
    bash miniforge.sh -b -p "$MF"
fi
export PATH="$MF/bin:$PATH"
python3 --version
# NEURON's build generates sources with jinja2 and reads yaml; these are build
# dependencies of the configure step, not runtime dependencies of the model.
"$MF/bin/pip" install -q jinja2 pyyaml setuptools packaging numpy 2>&1 | tail -2
ls "$MF/include/python3"*/Python.h >/dev/null && echo "Python headers: OK"

NVHPC_ROOT="$HOME/opt/nvhpc24/Linux_x86_64/24.11"
export PATH="$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"

SRC="$HOME/nrn_src"; BUILD="$SRC/build-gpu"; PREFIX="$HOME/opt/nrn-gpu"
[ -d "$SRC/.git" ] || git clone --depth 1 --branch 9.0.2 https://github.com/neuronsimulator/nrn.git "$SRC"
cd "$SRC" && git submodule update --init --recursive --depth 1 || true

rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=nvc \
    -DCMAKE_CXX_COMPILER=nvc++ \
    -DNRN_ENABLE_CORENEURON=ON \
    -DCORENRN_ENABLE_GPU=ON \
    -DCMAKE_CUDA_ARCHITECTURES="80;86" \
    -DCMAKE_CUDA_COMPILER="$NVHPC_ROOT/cuda/12.6/bin/nvcc" \
    -DNRN_ENABLE_INTERVIEWS=OFF \
    -DNRN_ENABLE_RX3D=OFF \
    -DNRN_ENABLE_MPI=OFF \
    -DNRN_ENABLE_PYTHON=ON \
    -DPYTHON_EXECUTABLE="$MF/bin/python3" \
    -DCMAKE_BUILD_TYPE=Release \
    > cmake.log 2>&1 || { echo "CMAKE FAILED"; grep -iE "error|could not" cmake.log | head -15; exit 1; }
echo "cmake ok; building on $(nproc) cores ..."

make -j"$(nproc)" > make.log 2>&1 || { echo "BUILD FAILED"; grep -iE "error" make.log | head -25; exit 1; }
make install > install.log 2>&1
echo "=== installed ==="
ls "$PREFIX/bin" | head
