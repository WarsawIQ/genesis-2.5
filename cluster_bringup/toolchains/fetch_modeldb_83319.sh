#!/bin/sh
# Fetch the reference implementation of the Vogels-Abbott COBAHH benchmark:
# ModelDB accession 83319 (Brette et al., J Comput Neurosci 23:349, 2007), whose
# NEURON/cobahh directory is the NEURON and CoreNEURON arm of Table 5.
#
# The archive is verified against the checksum of the copy the paper's runs
# used, and refused on any mismatch: a silently different model would make the
# comparison meaningless while still producing numbers.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"

URL=https://modeldb.science/download/83319
SHA=5eeb6188cf49212a299b10c820878a907b9822f3024fdac545a4c6a2b5f50519
ZIP="$MODELDB_DIR/ml83319.zip"

mkdir -p "$MODELDB_DIR"
if [ ! -s "$ZIP" ]; then
    echo "downloading $URL"
    curl -sSL --retry 3 -o "$ZIP.part" "$URL"
    mv "$ZIP.part" "$ZIP"
fi

got=$(sha256sum "$ZIP" | cut -d' ' -f1)
if [ "$got" != "$SHA" ]; then
    echo "ModelDB 83319: checksum mismatch" >&2
    echo "  expected $SHA" >&2
    echo "  got      $got" >&2
    echo "Refusing to use it. If ModelDB has changed the archive, the copy archived" >&2
    echo "with the release on Zenodo is the one the paper used." >&2
    exit 1
fi
echo "ModelDB 83319: checksum OK"

if [ ! -d "$MODELDB_DIR/destexhe_benchmarks" ]; then
    (cd "$MODELDB_DIR" && unzip -q "$ZIP")
fi
[ -f "$COBAHH_DIR/init.hoc" ] || { echo "no init.hoc in $COBAHH_DIR" >&2; exit 1; }
echo "COBAHH model at $COBAHH_DIR"
