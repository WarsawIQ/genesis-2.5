#!/bin/sh
# E6's four CPU profiles again, reported by library as well as by symbol.
#
#     sh cluster_bringup/campaign/profile_dso.sh <release checkout>
#
# E6 keeps each profile only as symbol percentages (profile_split.sh) and
# deletes perf.data. On v2.6.0-rc3 a third of the CoreNEURON spiking profile
# came out as bare addresses, which cannot be put in a category without
# knowing the library they belong to. This repeats E6's profiled runs (the
# same commands, workloads and perf settings: 499 Hz, call graphs, NUMA node
# 0) on the binaries of <release checkout> and keeps, per arm, the report by
# symbol (as E6), by library and by library and symbol. E6's timed runs and
# its profiled-run overhead check stay as measured on the night; this adds
# only the attribution. Needs perf and E6's work directory under $RUN_DIR
# (the CoreNEURON tree mechanisms are built there by E6).
#
# Writes logs/campaign_prep/profile_dso_<node>_<time>/: <arm>_symbols.txt,
# <arm>_dso.txt, <arm>_dso_symbols.txt, <arm>.log and run.txt.
set -u
[ $# -eq 1 ] || { echo "usage: $0 <release checkout>" >&2; exit 2; }
REL=$(cd "$1" && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
command -v perf >/dev/null || { echo "perf not found" >&2; exit 2; }
NUMA=${CAMPAIGN_NUMA:-0}
TN=10000; TK=1000
W=$RUN_DIR/campaign_E6
[ -f "$W/nrn_tree/x86_64/libcorenrnmech.so" ] || { echo "no $W/nrn_tree: run E6 first" >&2; exit 2; }
OUT=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/profile_dso_$(hostname -s)_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
P=$RUN_DIR/profile_dso.perf.data
{
echo "# node $(hostname -s); binaries from $(cd "$REL" && git describe --tags --always) $(cd "$REL" && git rev-parse HEAD)"
echo "# nxgenesis_nocl sha256 $(sha256sum "$REL/genesis/src/nxgenesis_nocl" | cut -d' ' -f1)"
echo "# $(perf --version); perf record -F 499 -g; numactl node $NUMA"
} > "$OUT/run.txt"

prof() {   # arm, then the command
    a=$1; shift
    rm -f "$P"
    t0=$(date +%s%N)
    numactl --cpunodebind="$NUMA" --membind="$NUMA" perf record -F 499 -g -o "$P" -- "$@" \
        > "$OUT/$a.log" 2>&1 < /dev/null
    rc=$?
    t1=$(date +%s%N)
    echo "$a: exit $rc, wall $(awk "BEGIN{printf \"%.2f\", ($t1 - $t0) / 1e9}") s" >> "$OUT/run.txt"
    perf report -i "$P" --stdio --no-children --sort symbol 2>/dev/null \
        | grep -E "^ +[0-9.]+%" > "$OUT/${a}_symbols.txt"
    perf report -i "$P" --stdio --no-children --sort dso 2>/dev/null \
        | grep -E "^ +[0-9.]+%" > "$OUT/${a}_dso.txt"
    perf report -i "$P" --stdio --no-children --sort dso,symbol 2>/dev/null \
        | grep -E "^ +[0-9.]+%" > "$OUT/${a}_dso_symbols.txt"
    rm -f "$P"
}

cd "$REL" || exit 2
G=$W/g_spk_dso; rm -rf "$G"; mkdir -p "$G"
cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$G"/
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
    "$REL" "$REL" "$REL" "$G" "$REL" > "$G/.simrc"

prof g_spk env -C "$G" timeout 3600 "$REL/genesis/src/nxgenesis_nocl" -notty -batch VAnet2-batch-1solver.g
prof cn_spk env -C "$COBAHH_DIR" PATH="$NRN_PIP_BIN:$PATH" timeout 3600 "$NRN_PYTHON" run_core.py
prof g_tree env GENESIS_BENCH_CHANMODE=1 GENESIS_BENCH_NCOMP=16 timeout 3600 \
    ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch \
    genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$TN" "$TK"
prof cn_tree env -C "$W/nrn_tree" USE_CORENEURON=1 USE_GPU=0 PATH="$NRN_PIP_BIN:$PATH" \
    timeout 3600 "$NRN_PYTHON" hh_multicomp_neuron.py "$TN" "$TK"
cat "$OUT/run.txt"
echo "written: $OUT"
