#!/bin/bash
# Build CoreNEURON's NMODL generator with GCC too, and resume.
#
# Same fault as nocmodl, one tool further along: bin/nmodl, built by nvc++,
# segfaults translating netstim.mod. Both are host tools that emit C++; the
# device code is compiled afterwards by nvc++ regardless, so which compiler
# built the generators does not affect what runs on the GPU.
#
# NMODL uses SymPy for its symbolic passes, so unlike nocmodl this host build
# needs Python enabled.
set -eu
NVHPC_ROOT="$HOME/opt/nvhpc24/Linux_x86_64/24.11"
MF="$HOME/opt/miniforge"
SRC="$HOME/nrn_src"; GPU="$SRC/build-gpu"; HOSTB="$SRC/build-hostnmodl"

export PATH="$MF/bin:$PATH"
[ -d /opt/rh/gcc-toolset-13/root/usr/bin ] && {
    export PATH="/opt/rh/gcc-toolset-13/root/usr/bin:$PATH"
    export LD_LIBRARY_PATH="/opt/rh/gcc-toolset-13/root/usr/lib64:${LD_LIBRARY_PATH:-}"
}
echo "host compiler: $(g++ --version | head -1)"
"$MF/bin/pip" install -q sympy jinja2 pyyaml 2>&1 | tail -1 || true

rm -rf "$HOSTB"; mkdir -p "$HOSTB"; cd "$HOSTB"
cmake .. \
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
    -DNRN_ENABLE_CORENEURON=ON -DCORENRN_ENABLE_GPU=OFF \
    -DNRN_ENABLE_INTERVIEWS=OFF -DNRN_ENABLE_RX3D=OFF -DNRN_ENABLE_MPI=OFF \
    -DNRN_ENABLE_PYTHON=ON -DPYTHON_EXECUTABLE="$MF/bin/python3" \
    -DCMAKE_BUILD_TYPE=Release > cmake_hostnmodl.log 2>&1 \
    || { echo "host cmake failed"; grep -iE "error" cmake_hostnmodl.log | head; exit 1; }

make -j"$(nproc)" nmodl > make_hostnmodl.log 2>&1 \
    || { echo "host nmodl build failed"; grep -iE "error" make_hostnmodl.log | tail -15; exit 1; }

GEN=$(find "$HOSTB" -name nmodl -type f -perm -u+x | head -1)
[ -n "$GEN" ] || { echo "no nmodl produced"; exit 1; }
echo "GCC nmodl: $GEN"
"$GEN" --version >/dev/null 2>&1 && echo "nmodl runs: OK" || { echo "GCC nmodl does not run"; exit 1; }

cp -f "$GEN" "$GPU/bin/nmodl"
echo "substituted $GPU/bin/nmodl"

export PATH="$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"
cd "$GPU"
make -j"$(nproc)" >> make.log 2>&1 || { echo "BUILD FAILED"; grep -iE "error|segmentation" make.log | tail -12; exit 1; }
make install >> install.log 2>&1
echo "=== installed ==="
ls "$HOME/opt/nrn-gpu/bin" 2>/dev/null | head
