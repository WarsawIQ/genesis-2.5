#!/bin/bash
# Python 3.13 with development headers, for Arbor and the NEURON GPU build.
#
# The cluster's own Pythons (3.6, 3.12) ship no Python.h, and both builds need
# it. Miniforge is self-contained and installs without root. It is pinned to the
# release the paper's builds used, and verified against its published checksum,
# rather than taken from "latest".
#
# From as-found/build_gpu_24.sh, which installed it on the way to the NEURON
# GPU build.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

VER=26.3.2-3
INST=Miniforge3-$VER-Linux-x86_64.sh
SHA=848194851a98903134187fbb4ab50efe87b003e0c0f808f97644b7524a62bf2c

if [ ! -x "$MINIFORGE/bin/python3" ]; then
    mkdir -p "$WORK_DIR/downloads"
    cd "$WORK_DIR/downloads"
    [ -s "$INST" ] || curl -sSL --retry 3 -o "$INST" \
        "https://github.com/conda-forge/miniforge/releases/download/$VER/$INST"
    echo "$SHA  $INST" | sha256sum -c --quiet - \
        || { echo "$INST: checksum mismatch, refusing" >&2; exit 1; }
    bash "$INST" -b -p "$MINIFORGE"
fi

# Build dependencies of NEURON's configure step (code generation, nmodl's
# symbolic passes), at the versions the paper's build used.
"$MINIFORGE/bin/pip" install -q \
    Jinja2==3.1.6 PyYAML==6.0.3 setuptools==82.0.1 packaging==26.2 \
    numpy==2.5.2 sympy==1.14.0

ls "$MINIFORGE"/include/python3*/Python.h >/dev/null \
    || { echo "no Python.h under $MINIFORGE/include" >&2; exit 1; }
echo "miniforge $VER: $("$MINIFORGE/bin/python3" --version)"
