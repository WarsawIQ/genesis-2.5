#!/bin/bash
# Build nocmodl with GCC and substitute it into the GPU build.
#
# Both NVHPC 25.3 and 24.11 produce a nocmodl that segfaults on every .mod file,
# so the fault is not a version mismatch: NEURON's lex/yacc-based code generator
# does not survive compilation by nvc++ at all. nocmodl is a host build tool --
# it emits C++ that is then compiled for the device -- so nothing about the GPU
# result depends on which compiler built the generator itself. Building that one
# tool with GCC and dropping it into the GPU tree leaves the offloaded code
# untouched.
set -eu
NVHPC_ROOT="$HOME/opt/nvhpc24/Linux_x86_64/24.11"
SRC="$HOME/nrn_src"
GPU="$SRC/build-gpu"
CPU="$SRC/build-hosttools"

export PATH="$HOME/opt/miniforge/bin:$PATH"

# The system GCC is 8.5, which needs an explicit -lstdc++fs for std::filesystem
# and fails to link nocmodl without it. gcc-toolset-13 is installed; use it.
if [ -d /opt/rh/gcc-toolset-13/root/usr/bin ]; then
    export PATH="/opt/rh/gcc-toolset-13/root/usr/bin:$PATH"
    export LD_LIBRARY_PATH="/opt/rh/gcc-toolset-13/root/usr/lib64:${LD_LIBRARY_PATH:-}"
fi
echo "host compiler: $(g++ --version | head -1)"

# 1. A plain GCC configure, only far enough to produce the generator.
rm -rf "$CPU"; mkdir -p "$CPU"; cd "$CPU"
cmake .. \
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
    -DNRN_ENABLE_PYTHON=OFF -DNRN_ENABLE_INTERVIEWS=OFF \
    -DNRN_ENABLE_RX3D=OFF -DNRN_ENABLE_MPI=OFF \
    -DNRN_ENABLE_CORENEURON=OFF \
    -DCMAKE_BUILD_TYPE=Release > cmake_host.log 2>&1 \
    || { echo "host cmake failed"; tail -20 cmake_host.log; exit 1; }

make -j"$(nproc)" nocmodl > make_host.log 2>&1 \
    || { echo "host nocmodl build failed"; grep -iE "error" make_host.log | head; exit 1; }

GEN=$(find "$CPU" -name nocmodl -type f -perm -u+x | head -1)
[ -n "$GEN" ] || { echo "no nocmodl produced"; exit 1; }
echo "GCC nocmodl: $GEN"

# Prove it works before substituting it: a generator that segfaults here would
# fail identically in the GPU tree.
printf 'NEURON { SUFFIX probe }\nASSIGNED { v }\n' > /tmp/probe_$$.mod
( cd /tmp && "$GEN" "probe_$$.mod" >/dev/null 2>&1 ) \
    && echo "generator translates a .mod file: OK" \
    || { echo "GCC-built nocmodl also fails -- the fault is not the compiler"; exit 1; }
rm -f /tmp/probe_$$.mod /tmp/probe_$$.cpp

# 2. Substitute into the GPU tree.
for t in "$GPU/bin/nocmodl" "$GPU/nocmodl"; do
    if [ -e "$t" ]; then cp -f "$GEN" "$t"; echo "replaced $t"; fi
done
mkdir -p "$GPU/bin"; cp -f "$GEN" "$GPU/bin/nocmodl"

# 3. Resume the GPU build.
export PATH="$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"
cd "$GPU"
make -j"$(nproc)" >> make.log 2>&1 || { echo "BUILD FAILED"; grep -iE "error|segmentation" make.log | tail -12; exit 1; }
make install >> install.log 2>&1
echo "=== installed ==="
ls "$HOME/opt/nrn-gpu/bin" 2>/dev/null | head
