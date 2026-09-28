#!/bin/bash
# The NVHPC SDK, for CoreNEURON's OpenACC GPU backend. The cluster has the CUDA
# toolkit but no nvc++, so this installs one without root.
#
# 24.11, not the current release: nvc++ 25.3 miscompiles NEURON's nocmodl code
# generator, which then segfaults on every .mod file. 24.11 is what NEURON's
# own CI builds against. (Its nocmodl crashes too; 30_neuron_gpu.sh deals with
# that.) The single-CUDA 12.6 package is 6.1 GB to download, 13 GB installed.
#
# From as-found/install_nvhpc24.sh. NVIDIA publishes no checksum for the
# tarball; the one below is the copy the paper's build was installed from.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

VER=24.11
PKG=nvhpc_2024_2411_Linux_x86_64_cuda_12.6
SHA=39408ac062573936e0d41f34530ab065998ef4b85b6bcccb59287d71135a1920
DEST=${NVHPC_ROOT%/Linux_x86_64/*}

if [ -x "$NVHPC_ROOT/compilers/bin/nvc++" ]; then
    echo "NVHPC already installed: $("$NVHPC_ROOT/compilers/bin/nvc++" --version | grep -m1 nvc++)"
    exit 0
fi

mkdir -p "$WORK_DIR/downloads" "$DEST"
cd "$WORK_DIR/downloads"
[ -s "$PKG.tar.gz" ] || curl -sSL --retry 3 -C - -o "$PKG.tar.gz" \
    "https://developer.download.nvidia.com/hpc-sdk/$VER/$PKG.tar.gz"
echo "$SHA  $PKG.tar.gz" | sha256sum -c --quiet - \
    || { echo "$PKG.tar.gz: checksum mismatch, refusing" >&2; exit 1; }

[ -d "$PKG" ] || tar xpzf "$PKG.tar.gz"
cd "$PKG"
NVHPC_SILENT=true NVHPC_INSTALL_DIR="$DEST" NVHPC_INSTALL_TYPE=single ./install

"$NVHPC_ROOT/compilers/bin/nvc++" --version | grep -m1 nvc++
