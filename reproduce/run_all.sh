#!/bin/sh
# Measure the revised paper's numbers again, on your machine.
#
#   sh reproduce/run_all.sh --cpu-only --quick   no GPU: model construction, the CPU
#                                                solver's modes, the CPU's action potential
#   sh reproduce/run_all.sh --cpu-only           the same, construction up to 1.7 million
#                                                compartments
#   sh reproduce/run_all.sh --quick              with an NVIDIA GPU: adds Table 2, the
#                                                speedup against run length, CUDA Graphs
#   sh reproduce/run_all.sh                      adds the whole tree sweep, the work
#                                                imbalance and the 10 s spiking run
#   ... --with-simulators                        adds Table 3 and the crossover with Arbor
#                                                (NEURON, CoreNEURON and Arbor installed by
#                                                cluster_bringup/toolchains/)
#
# The times each mode took on our machines are in reproduce/README.md.
#
# It runs the stages that measured the paper (cluster_bringup/campaign/) in a
# reader's mode: CAMPAIGN_DRY=1, REPRO=quick|full, every file under
# reproduce/results/, so a reader's data never mix with the paper's. Each stage
# keeps its checks: a GPU in use by another job is waited for and then refused,
# the start-up banner must name the backend and precision asked for, and a run
# that did not do its work is rejected and retried once. measure.py then
# computes every number of the paper that this run measured, with the same
# extractor as the published value, and prints both with a verdict.
#
# Needs: Linux x86_64, GCC, GNU make, flex, bison, ncurses, Python 3.6+; for the
# GPU modes a CUDA 12.x toolkit and an NVIDIA GPU (OpenCL is used when it
# builds, and skipped otherwise).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
GENESIS_ROOT=${GENESIS_ROOT:-$ROOT}
export GENESIS_ROOT
. "$ROOT/cluster_bringup/env.sh"

MODE=full CPU_ONLY=0 WITH_SIM=0
for a in "$@"; do
    case "$a" in
        --quick) MODE=quick ;;
        --cpu-only) CPU_ONLY=1 ;;
        --with-simulators|--with-neuron) WITH_SIM=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
    esac
done

RESULTS=${RESULTS:-$HERE/results}
rm -rf "$RESULTS"          # one run's results at a time: measure.py reads all it finds
mkdir -p "$RESULTS/campaign" "$RESULTS/chanmode" "$RESULTS/runs"
CAMPAIGN_DRY=1 REPRO=$MODE CAMPAIGN_OUT="$RESULTS/campaign" CHANMODE_OUT="$RESULTS/chanmode"
RUN_DIR="$RESULTS/runs" CAMPAIGN_NODE=${CAMPAIGN_NODE:-reader}
export CAMPAIGN_DRY REPRO CAMPAIGN_OUT CHANMODE_OUT RUN_DIR CAMPAIGN_NODE
cd "$ROOT" || exit 1

say() { printf '\n=== %s ===\n' "$1"; }
FAILED=""
stage() {   # <name> <command...>: run one stage, keep going if it fails
    name=$1; shift
    say "$name"
    t0=$(date +%s)
    "$@" 2>&1 | tee "$RESULTS/$name.log" | grep -E "^\[|REFUSED|^ok|^FAIL|written" | tail -40
    echo "($name: $(( $(date +%s) - t0 )) s)"
}
run() {     # <name> <command...>, recording the exit code
    name=$1; shift
    stage "$name" sh -c '"$@"; echo $? > "$0"' "$RESULTS/.status_$name" "$@"
    rc=$(cat "$RESULTS/.status_$name" 2>/dev/null || echo 1)
    [ "$rc" = 0 ] || FAILED="$FAILED $name($rc)"
}

T_START=$(date +%s)
say "environment"
uname -srm
gcc --version | head -1
python3 --version
echo "mode: $MODE$([ "$CPU_ONLY" = 1 ] && echo ', cpu only')$([ "$WITH_SIM" = 1 ] && echo ', with simulators'); results in $RESULTS"

# ---------------------------------------------------------------------- build
if [ "$CPU_ONLY" = 1 ]; then
    say "build (CPU only)"
    if [ -x genesis/src/nxgenesis_nocl ] && [ "${SKIP_BUILD:-0}" = 1 ]; then
        echo "using the existing binary (SKIP_BUILD=1)"
    else
        sh cluster_bringup/12_build_cpu.sh > "$RESULTS/build.log" 2>&1 \
            || { echo "build failed, see $RESULTS/build.log" >&2; tail -20 "$RESULTS/build.log"; exit 1; }
        echo "built genesis/src/nxgenesis_nocl"
    fi
else
    command -v nvidia-smi > /dev/null 2>&1 \
        || { echo "nvidia-smi not found: the GPU modes need an NVIDIA GPU (or use --cpu-only)" >&2; exit 1; }
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    [ -x "$CUDA_HOME/bin/nvcc" ] && PATH="$CUDA_HOME/bin:$PATH" && export PATH
    command -v nvcc > /dev/null 2>&1 || { echo "nvcc not found; set CUDA_HOME" >&2; exit 1; }
    say "build"
    if [ "${SKIP_BUILD:-0}" = 1 ] && [ -x genesis/src/nxgenesis ] && [ -x genesis/src/nxgenesis_nocl ]; then
        echo "using the existing binaries (SKIP_BUILD=1)"
    else
        # OpenCL first (10_build.sh cleans between the builds it makes); optional
        if sh cluster_bringup/11_build_opencl.sh > "$RESULTS/build_opencl.log" 2>&1 \
           && [ -x genesis/src/nxgenesis_ocl ]; then
            echo "built genesis/src/nxgenesis_ocl"
        else
            echo "no OpenCL build here ($RESULTS/build_opencl.log): Table 2's OpenCL columns are skipped"
        fi
        sh cluster_bringup/10_build.sh > "$RESULTS/build.log" 2>&1 \
            || { echo "build failed, see $RESULTS/build.log" >&2; tail -20 "$RESULTS/build.log"; exit 1; }
        echo "built genesis/src/nxgenesis and genesis/src/nxgenesis_nocl"
    fi
fi

# ------------------------------------------------- the action potential check
# hh1952_ap_verify.g: 8 neurons under one hsolve must fire the same action
# potential (the Hines-solver fixes); its membrane potential, in the golden's
# format, is the CPU value the paper's fp32 deviation is measured against.
say "action potential, 8 neurons under one solver"
ap() {   # <label> <binary> [env...]
    label=$1 bin=$2; shift 2
    env "$@" timeout 600 "$bin" -nosimrc -notty -batch genesis/Scripts/benchmark/hh1952_ap_verify.g 8 200 \
        < /dev/null 2>&1 | grep -E "^(RESULT_VM=|NEURONS_AGREE:)" | sed "s|^|$label\||"
}
{
    ap ap_cpu ./genesis/src/nxgenesis_nocl
    [ "$CPU_ONLY" = 1 ] || ap ap_gpu ./genesis/src/nxgenesis GENESIS_CUDA_MULTILOOP=210
} | tee "$RESULTS/ap_check.txt"
grep -q "NEURONS_AGREE: YES" "$RESULTS/ap_check.txt" || FAILED="$FAILED action_potential"

# --------------------------------------------------------------------- stages
REPS_CM=1; [ "$MODE" = full ] && REPS_CM=3
run chanmode sh cluster_bringup/campaign/chanmode_check.sh "$ROOT" "$REPS_CM"
run E3c sh cluster_bringup/campaign/E3c_cpu.sh
if [ "$CPU_ONLY" = 0 ]; then
    run E2 sh cluster_bringup/campaign/E2_ksweep.sh
    run E3 sh cluster_bringup/campaign/E3_tables.sh
    run E8 sh cluster_bringup/campaign/E8_graphs.sh
    if [ "$MODE" = full ]; then
        run E7 sh cluster_bringup/campaign/E7_imbalance.sh
        run E5 sh cluster_bringup/campaign/E5_long_run.sh
    fi
    if [ "$WITH_SIM" = 1 ]; then
        run E1 sh cluster_bringup/campaign/E1_cross_simulator.sh
        run E4 sh cluster_bringup/campaign/E4_fp64_cost.sh
    fi
fi

# ------------------------------------------------------------------ verdicts
say "tidy"
for f in "$RESULTS"/campaign/E*_*.csv; do
    case "$f" in *_tidy.csv|*_spikes.csv|*_report.csv) continue ;; esac
    [ -f "$f" ] && python3 cluster_bringup/campaign/tidy.py "$f"
done
say "the paper's numbers, measured here"
python3 "$HERE/measure.py" "$RESULTS"; mrc=$?
echo
echo "total: $(( ($(date +%s) - T_START) / 60 )) min; raw results and logs: $RESULTS"
if [ -n "$FAILED" ]; then
    echo "stages that did not complete:$FAILED (see their logs in $RESULTS)"
    exit 1
fi
exit $mrc
