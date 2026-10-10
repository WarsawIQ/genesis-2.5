#!/bin/sh
# E6: why GENESIS and CoreNEURON rank differently on the two workloads
# (reviewer point 3), measured rather than argued. CPU profiles (perf, 499 Hz,
# call graphs) of the GENESIS and CoreNEURON CPU arms on the spiking network
# and on the dendritic-tree model, reported by symbol and by library and split
# into channel update, linear solve, synapses and events, element dispatch and
# the rest (profile_split.sh, profile_categories_dso.txt). Each arm also
# runs 3 times without the profiler; the profiled run must be within 5% of
# their mean, or the profile is reported as distorting. Run on inf03. ~40 min.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-3}; TN=10000; TK=1000
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && TN=1000 && TK=200
campaign_init E6
command -v perf >/dev/null || { echo "REFUSED: perf not found on $NODE" >&2; exit 2; }
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need "$COBAHH_DIR/x86_64" "coreneuron/build_mechanisms.sh cpu"
W="$RUN_DIR/campaign_E6"; mkdir -p "$W"
vanet2_workdir "$W/g_spk"
mkdir -p "$W/nrn_tree"
if [ ! -f "$W/nrn_tree/x86_64/libcorenrnmech.so" ]; then
    ( cd "$W/nrn_tree" && PATH="$NRN_PIP_BIN:$PATH" nrnivmodl -coreneuron . ) > "$W/nrn_tree/build.log" 2>&1
fi
need "$W/nrn_tree/x86_64/libcorenrnmech.so" "nrnivmodl -coreneuron, see $W/nrn_tree/build.log"
cp -f cluster_bringup/coreneuron/hh_multicomp_neuron.py "$W/nrn_tree/"

PERF=""   # set to a perf record prefix for the profiled runs
arm() {   # g_spk, cn_spk, g_tree, cn_tree (+ _perf for the profiled run)
    unset EXPECT_NCOMP EXPECT_SPIKES SPIKES_OF
    a=${1%_perf}
    case "$a" in
    g_spk)  EXPECT_NCOMP=4000
            run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_vanet2 \
                env -C "$W/g_spk" $PERF timeout 3600 "$GENESIS_ROOT/genesis/src/nxgenesis_nocl" \
                -notty -batch VAnet2-batch-1solver.g ;;
    cn_spk) SANITY_RE='.' SANITY_METRIC=ran
            run_rep "$1" "$2" "$3" 0 "$BANNER_ANY" sanity_grep \
                env -C "$COBAHH_DIR" PATH="$NRN_PIP_BIN:$PATH" $PERF timeout 3600 "$NRN_PYTHON" run_core.py ;;
    g_tree) tree_rep "$1" "$2" "$3" cpu "$TN" "$TK" 16 ;;
    cn_tree) SANITY_RE='^RESULT_' SANITY_METRIC=result
            run_rep "$1" "$2" "$3" 0 "$BANNER_ANY" sanity_grep \
                env -C "$W/nrn_tree" USE_CORENEURON=1 USE_GPU=0 PATH="$NRN_PIP_BIN:$PATH" \
                $PERF timeout 3600 "$NRN_PYTHON" hh_multicomp_neuron.py "$TN" "$TK" ;;
    esac
}
run_arms "$REPS" arm g_spk cn_spk g_tree cn_tree; st=$?

# One profiled run per arm. tree_rep builds its own command, so g_tree's
# profiled run is spelled out here.
for a in g_spk cn_spk g_tree cn_tree; do
    P="$RUNS/${a}.perf.data"
    PERF="perf record -F 499 -g -o $P --"
    if [ "$a" = g_tree ]; then
        EXPECT_N=$TN EXPECT_STEPS=$TK EXPECT_NCOMP=16
        run_rep "${a}_perf" 1 1 0 "$BANNER_CPU" sanity_tree \
            env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 $PERF timeout 3600 \
            ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch \
            genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$TN" "$TK" || st=$?
    else
        arm "${a}_perf" 1 1 || st=$?
    fi
    [ -f "$P" ] && sh cluster_bringup/campaign/profile_split.sh "$P" "${CSV%.csv}_$a" \
        && rm -f "$P"
done
PERF=""
campaign_done "$st" --single=g_spk_perf,cn_spk_perf,g_tree_perf,cn_tree_perf "perf_overhead_g_spk=g_spk_perf/g_spk" "perf_overhead_cn_spk=cn_spk_perf/cn_spk" \
    "perf_overhead_g_tree=g_tree_perf/g_tree" "perf_overhead_cn_tree=cn_tree_perf/cn_tree"
exit $st
