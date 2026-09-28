#!/bin/bash
# Install the NVHPC SDK into $HOME so CoreNEURON can be built with GPU support.
#
# nvc++ 25.3 miscompiles NEURON's own nocmodl code generator, which then segfaults
# translating every .mod file. 24.11 is the toolchain NEURON's CI is built against.
# toolkit alone is not enough, and the cluster has no nvc++. This installs
# locally, without root. The cuda_12.8 single-CUDA package is chosen to match
# the toolkit GENESIS already builds against (7.9 GB rather than 12.2 GB for
# the multi-CUDA bundle).
set -eu
VER=24.11
PKG=nvhpc_2024_2411_Linux_x86_64_cuda_12.6
DEST="$HOME/opt/nvhpc24"
WORK="$HOME/nvhpc_dl"

mkdir -p "$WORK" "$DEST"
cd "$WORK"

if [ ! -s "$PKG.tar.gz" ]; then
    echo "downloading $PKG.tar.gz ..."
    curl -sSL --retry 3 -C - -o "$PKG.tar.gz" \
        "https://developer.download.nvidia.com/hpc-sdk/$VER/$PKG.tar.gz"
fi
ls -la "$PKG.tar.gz"

if [ ! -d "$PKG" ]; then
    echo "extracting ..."
    tar xpzf "$PKG.tar.gz"
fi

echo "installing to $DEST ..."
cd "$PKG"
NVHPC_SILENT=true \
NVHPC_INSTALL_DIR="$DEST" \
NVHPC_INSTALL_TYPE=single \
./install

echo "=== result ==="
find "$DEST" -maxdepth 4 -name nvc++ -type f 2>/dev/null | head -3
