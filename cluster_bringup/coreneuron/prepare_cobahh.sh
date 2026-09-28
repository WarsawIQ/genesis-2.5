#!/bin/sh
# Turn a fresh ModelDB 83319 into the model the NEURON and CoreNEURON arms of
# Table 5 ran: apply cobahh_vanet2.patch and install the run drivers.
#
#     sh cluster_bringup/toolchains/fetch_modeldb_83319.sh
#     sh cluster_bringup/coreneuron/prepare_cobahh.sh           # 4000 cells
#     NCELL=12500 sh cluster_bringup/coreneuron/prepare_cobahh.sh
#
# The edits used to be made by hand in the cluster copy and described only in
# README.md. One of them, ncell, was raised for a scaling experiment and never
# set back, so anyone re-running the harness later would have timed a network
# three times the size. Here the patch fixes the model and NCELL is explicit.
#
# Drivers (from the cluster copy, where they were written; originals in
# ../toolchains/as-found/):
#   run_plain.py  NEURON, CPU            run_core.py  CoreNEURON, CPU
set -eu
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
HERE="$GENESIS_ROOT/cluster_bringup/coreneuron"
NCELL=${NCELL:-4000}
NEURON_DIR=$(dirname "$COBAHH_DIR")     # .../destexhe_benchmarks/NEURON

[ -f "$COBAHH_DIR/init.hoc" ] || { echo "run toolchains/fetch_modeldb_83319.sh first" >&2; exit 1; }

# The patch names NEURON/... paths, so it applies from the directory above.
cd "$(dirname "$NEURON_DIR")"
if grep -q 'Random123' NEURON/common/ranstream.hoc; then
    echo "cobahh_vanet2.patch already applied"
else
    patch -p1 --forward --no-backup-if-mismatch < "$HERE/cobahh_vanet2.patch"
fi
cd "$NEURON_DIR"

# The one parameter an experiment may change, set explicitly every time.
sed -i "s/^ncell = [0-9]*$/ncell = $NCELL/" common/init.hoc
grep -q "^ncell = $NCELL$" common/init.hoc || { echo "could not set ncell" >&2; exit 1; }

cp -f "$HERE/run_plain.py" "$HERE/run_core.py" "$COBAHH_DIR/"
echo "COBAHH ready in $COBAHH_DIR: ncell=$NCELL, tstop 5000 ms, dt 0.05 ms, Random123"
