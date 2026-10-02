#!/bin/sh
# E3, CPU part: model construction against model size (Fig. 11), and PGENESIS
# strong scaling on MPI, 3 replicates each. Needs no GPU; run on a cluster node
# with at least 24 cores and nothing else running.
#
# Construction: hh_branching_multicompartment_benchmark.g, 4 branches of 4
# compartments (17 per neuron), 20 steps, N = 1000 ... 100 000 (1.7 million
# compartments), timed around the whole process, as reproduce/stages/05_cpu.sh.
# Only the release is measured: the "before" curve is the code before the fix,
# which this tag no longer contains; its data stay as recorded in August.
#
# PGENESIS: hh1952_mpi_scaling.g, 2400 neurons, 5000 steps, P = 1 ... 24 ranks,
# as paper/scripts/run_pgenesis_mpi_scaling.sh. Needs pgenesis/bin/Linux/nxpgenesis
# (cluster_bringup/70_pgenesis_build_status.md).
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-3}
CN="1000 2000 4000 8000 16000 31000 62000 100000"
PLIST="1 2 4 6 8 12 16 20 24"
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1} && CN="1000 4000" && PLIST="1 2"
campaign_init E3c
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh or 12_build_cpu.sh"
PGEN=pgenesis/bin/Linux/nxpgenesis
need "$PGEN" "PGENESIS build, cluster_bringup/70_pgenesis_build_status.md"
[ "$(nproc)" -ge 24 ] || [ "$CAMPAIGN_DRY" = 1 ] || { echo "REFUSED: $(nproc) cores, 24 ranks need 24" >&2; exit 2; }

arm() {   # con_n<N>, mpi_p<P>
    case "$1" in
    con_n*)
        EXPECT_N=${1#con_n} EXPECT_STEPS=20; unset EXPECT_NCOMP
        run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_tree \
            env GENESIS_BENCH_CHANMODE=1 timeout 3600 ./genesis/src/nxgenesis_nocl -nosimrc -notty \
            -batch genesis/Scripts/benchmark/hh_branching_multicompartment_benchmark.g "$EXPECT_N" 20 4 4 ;;
    mpi_p*)
        p=${1#mpi_p}
        SANITY_RE='^PGENESIS_DONE' SANITY_METRIC=ranks
        run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_grep \
            timeout 1800 "$MPIRUN" -np "$p" "$PGEN" -nosimrc -notty \
            -batch genesis/Scripts/benchmark/hh1952_mpi_scaling.g 2400 "$p" 5000 0 ;;
    esac
}
ARMS=""; RATIOS=""
for n in $CN; do ARMS="$ARMS con_n$n"; done
for p in $PLIST; do ARMS="$ARMS mpi_p$p"; RATIOS="$RATIOS mpi_speedup_p$p=mpi_p1/mpi_p$p"; done
run_arms "$REPS" arm $ARMS; st=$?
campaign_done "$st" $RATIOS
exit $st
