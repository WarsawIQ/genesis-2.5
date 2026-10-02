# Checks that a run did its work, one function per workload. Sourced by E*.sh.
#
# Each function gets the run's log and wall time. It prints "<metric> <value>"
# and returns 0 when the run is sound, or prints the reason and returns 1.
# A run that exits 0 and prints nothing useful (a binary that never started
# was once timed at 1.8 ms instead of 8 s) is rejected here, not by eye.
#
# What a run must show is set by the stage before it calls run_rep:
#   EXPECT_N, EXPECT_NCOMP, EXPECT_STEPS   requested model size and run length
#   EXPECT_SPIKES                          reference spike count (+-20%)
#   SANITY_RE                              a line the run must print (generic check)
# and the plausible wall-time band per arm comes from bands.csv (arm,min_s,max_s),
# optional; without a band, a run under 0.02 s is rejected (the shortest real
# run, Table 2 at N = 100, takes about 0.13 s; a binary that never started, 2 ms).

BANDS=${BANDS:-$GENESIS_ROOT/cluster_bringup/campaign/bands.csv}

band_ok() {   # $1 wall time; uses $arm from run_rep
    lo=0.02; hi=1e9
    if [ -f "$BANDS" ]; then
        b=$(grep "^$arm," "$BANDS" | head -1)
        [ -n "$b" ] && lo=$(echo "$b" | cut -d, -f2) && hi=$(echo "$b" | cut -d, -f3)
    fi
    awk -v w="$1" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !(w >= lo && w <= hi)}' && return 0
    echo "wall time $1 s outside the plausible band $lo-$hi s"
    return 1
}

value_of() { sed -n "s/^$1[[:space:]]*//p" "$2" | head -1 | tr -d ' '; }

# hh_multicompartment_createmap.g, hh_branching_multicompartment_benchmark.g
sanity_tree() {
    band_ok "$2" || return 1
    t=$(value_of "RESULT_T_PER_STEP=" "$1")
    [ -n "$t" ] || { echo "no RESULT_T_PER_STEP line"; return 1; }
    d=$(grep "^=== done: N=" "$1" | head -1)
    [ -n "$d" ] || { echo "no closing '=== done' line"; return 1; }
    n=$(echo "$d" | sed -n 's/.*N= *\([0-9]*\).*/\1/p')
    [ -z "${EXPECT_N:-}" ] || [ "$n" = "$EXPECT_N" ] || { echo "built N=$n, asked for $EXPECT_N"; return 1; }
    if [ -n "${EXPECT_NCOMP:-}" ]; then
        c=$(echo "$d" | sed -n 's/.*NCOMP= *\([0-9,]*\).*/\1/p')
        [ "$c" = "$EXPECT_NCOMP" ] || { echo "built NCOMP=$c, asked for $EXPECT_NCOMP"; return 1; }
    fi
    s=$(echo "$d" | sed -n 's/.*steps= *\([0-9]*\).*/\1/p')
    [ -z "${EXPECT_STEPS:-}" ] || [ "$s" = "$EXPECT_STEPS" ] || { echo "ran $s steps, asked for $EXPECT_STEPS"; return 1; }
    echo "t_per_step_s $t"
}

# hh_spiking_benchmark.g (single-compartment, Table 1)
sanity_single() {
    band_ok "$2" || return 1
    n=$(value_of "Neurons:" "$1")
    [ -n "$n" ] || { echo "no 'Neurons:' line"; return 1; }
    [ -z "${EXPECT_N:-}" ] || [ "$n" = "$EXPECT_N" ] || { echo "built N=$n, asked for $EXPECT_N"; return 1; }
    s=$(value_of "Steps:" "$1")
    [ -z "${EXPECT_STEPS:-}" ] || [ "$s" = "$EXPECT_STEPS" ] || { echo "ran $s steps, asked for $EXPECT_STEPS"; return 1; }
    echo "neurons $n"
}

# VAnet2-batch.g, VAnet2-batch-1solver.g (timing runs print no spike count)
sanity_vanet2() {
    band_ok "$2" || return 1
    grep -q "^END  :" "$1" || { echo "no END line: the simulation did not finish"; return 1; }
    ex=$(value_of "Ex solver ncompts:" "$1"); in=$(value_of "Inh solver ncompts:" "$1")
    if [ -n "$ex" ]; then
        [ $((ex + in)) = "${EXPECT_NCOMP:-$((ex + in))}" ] \
            || { echo "solvers hold $((ex + in)) compartments, expected $EXPECT_NCOMP"; return 1; }
        echo "ncompts $((ex + in))"
    else
        echo "finished 1"
    fi
}

# a spike file written by GENESIS_VANET2_SPIKEFILE, or any run that reports a count
sanity_spikes() {   # needs SPIKES_OF: a command printing the count for the log $1
    band_ok "$2" || return 1
    n=$($SPIKES_OF "$1" 2>/dev/null)
    [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null || { echo "no spike count"; return 1; }
    if [ -n "${EXPECT_SPIKES:-}" ]; then
        awk -v n="$n" -v e="$EXPECT_SPIKES" 'BEGIN{exit !(n >= 0.8*e && n <= 1.2*e)}' \
            || { echo "$n spikes, reference $EXPECT_SPIKES (more than 20% apart)"; return 1; }
    fi
    echo "spikes $n"
}

# generic: the run must print a line matching SANITY_RE; its last number is the metric
sanity_grep() {
    band_ok "$2" || return 1
    l=$(grep -E "$SANITY_RE" "$1" | tail -1)
    [ -n "$l" ] || { echo "no line matching $SANITY_RE"; return 1; }
    v=$(echo "$l" | grep -oE '[-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?' | tail -1)
    echo "${SANITY_METRIC:-value} ${v:-1}"
}
