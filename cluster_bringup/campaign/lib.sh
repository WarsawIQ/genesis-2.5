# Shared harness for the revision measurement campaign. Sourced by E*.sh.
#
# Every number the revised paper reports is measured through these functions,
# so every run records the same header, refuses a GPU another job is using,
# checks that the binary started in the requested backend and precision, and
# rejects runs whose output shows they did not do their work. The history of
# this project is a list of silent failures (a foreign job inflating the A100
# by ~30%, a binary that never started timed as 1.8 ms, results printed only
# to a terminal); each check below answers one of them.
#
# Files, under $CAMPAIGN_OUT:
#   <exp>_<session>.csv         one row per run, header lines start with '#'
#   rejected.csv                every rejected run with its reason
#   runs/<session>/<arm>_r<rep>[_try2].log   full output of each run
#   <exp>_<node>.open           the session to resume, while one is unfinished
#
# Environment (see cluster_bringup/campaign/README.md):
#   CAMPAIGN_TAG   tag HEAD must be at (default v2.6.0-rc1)
#   CAMPAIGN_DRY   1 = untagged or dirty tree allowed, data go to campaign_dry/
#   CAMPAIGN_WAIT_S, CAMPAIGN_WAIT_TRIES   busy-GPU retry (600 s, 6 tries)
#   NVIDIA_SMI     nvidia-smi to call (the tests substitute a stub)

GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
CAMPAIGN_TAG=${CAMPAIGN_TAG:-v2.6.0-rc1}
CAMPAIGN_DRY=${CAMPAIGN_DRY:-0}
CAMPAIGN_WAIT_S=${CAMPAIGN_WAIT_S:-600}
CAMPAIGN_WAIT_TRIES=${CAMPAIGN_WAIT_TRIES:-6}
CAMPAIGN_MEM_MIB=${CAMPAIGN_MEM_MIB:-100}   # memory in use on an idle card, at most
NVSMI=${NVIDIA_SMI:-nvidia-smi}
NODE=${CAMPAIGN_NODE:-$(hostname -s)}

say() { echo "[$(date +%H:%M:%S)] $*"; }

has_gpu() { command -v "${NVSMI%% *}" >/dev/null 2>&1 && $NVSMI -L >/dev/null 2>&1; }

# ------------------------------------------------------------------ header
header() {   # the run header of data-model.md, as '# key: value' lines
    echo "# experiment: $EXP"
    echo "# session: $SESSION"
    echo "# commit: $COMMIT"
    echo "# describe: $DESCRIBE"
    echo "# dirty: $DIRTY"
    echo "# node: $NODE"
    echo "# cpu: $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
    echo "# governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
    echo "# loadavg: $(cut -d' ' -f1-3 /proc/loadavg)"
    if has_gpu; then
        echo "# gpu: $($NVSMI --query-gpu=name --format=csv,noheader | head -1)"
        echo "# driver: $($NVSMI --query-gpu=driver_version --format=csv,noheader | head -1)"
        echo "# cuda: $("$CUDA_HOME/bin/nvcc" --version 2>/dev/null | sed -n 's/.*release \([0-9.]*\).*/\1/p')"
        echo "# persistence: $($NVSMI --query-gpu=persistence_mode --format=csv,noheader | head -1)"
        echo "# sm_clock_mhz: $($NVSMI --query-gpu=clocks.sm,clocks.max.sm --format=csv,noheader,nounits | head -1 | sed 's/, / \/ /')"
        echo "# clock_reasons: $($NVSMI --query-gpu=clocks_event_reasons.active --format=csv,noheader 2>/dev/null | head -1)"
        echo "# gpu_mem_used_mib: $($NVSMI --query-gpu=memory.used --format=csv,noheader,nounits | head -1)"
        p=$($NVSMI --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null)
        echo "# gpu_processes: ${p:-none}" | tr '\n' ';' | sed 's/;$/\n/'
    else
        echo "# gpu: none"
    fi
}

# ------------------------------------------------------------- init / done
campaign_init() {   # $1 experiment id, e.g. E1
    EXP=$1
    cd "$GENESIS_ROOT" || exit 2
    COMMIT=$(git rev-parse HEAD)
    DESCRIBE=$(git describe --tags --exact-match 2>/dev/null || echo untagged)
    DIRTY=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
    if [ "$CAMPAIGN_DRY" = 1 ]; then
        CAMPAIGN_OUT=${CAMPAIGN_OUT:-$GENESIS_ROOT/cluster_bringup/logs/campaign_dry}
    else
        if [ "$DESCRIBE" != "$CAMPAIGN_TAG" ] || [ "$DIRTY" != 0 ]; then
            echo "REFUSED: HEAD is $DESCRIBE with $DIRTY changed files; the campaign runs" \
                 "only on a clean checkout of $CAMPAIGN_TAG (CAMPAIGN_DRY=1 for a dry run)" >&2
            exit 2
        fi
        CAMPAIGN_OUT=${CAMPAIGN_OUT:-$GENESIS_ROOT/cluster_bringup/logs/campaign_$CAMPAIGN_TAG}
    fi
    mkdir -p "$CAMPAIGN_OUT"
    OPEN="$CAMPAIGN_OUT/${EXP}_${NODE}.open"
    if [ -f "$OPEN" ]; then
        SESSION=$(cat "$OPEN")
        say "$EXP: resuming session $SESSION"
    else
        SESSION=${NODE}_$(date +%Y%m%d_%H%M%S)
        echo "$SESSION" > "$OPEN"
    fi
    CSV="$CAMPAIGN_OUT/${EXP}_${SESSION}.csv"
    RUNS="$CAMPAIGN_OUT/runs/$SESSION"
    mkdir -p "$RUNS"
    if [ ! -f "$CSV" ]; then
        { header; echo "session,experiment,arm,rep,order,wall_s,metric,metric_value,status,started"; } > "$CSV"
    else
        echo "# resumed: $(date -Is)" >> "$CSV"
    fi
    [ -f "$CAMPAIGN_OUT/rejected.csv" ] || \
        echo "session,experiment,arm,rep,try,wall_s,reason,log" > "$CAMPAIGN_OUT/rejected.csv"
    say "$EXP: session $SESSION, $DESCRIBE ($COMMIT), data $CSV"
}

campaign_done() {   # $1 = 0 when every arm has all its replicates; then ratios for report.py
    {
        echo "# ended: $(date -Is)"
        has_gpu && echo "# sm_clock_mhz_after: $($NVSMI --query-gpu=clocks.sm,clocks.max.sm --format=csv,noheader,nounits | head -1 | sed 's/, / \/ /')"
        echo "# complete: $([ "$1" = 0 ] && echo yes || echo no)"
    } >> "$CSV"
    [ "$1" = 0 ] && rm -f "$OPEN"
    shift
    python3 "$GENESIS_ROOT/cluster_bringup/campaign/report.py" "$CSV" "$@" || true
}

# --------------------------------------------------------------- busy GPU
gpu_busy() {   # prints why the GPU is not free; empty output = free
    has_gpu || return 0
    p=$($NVSMI --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null)
    m=$($NVSMI --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    if [ -n "$p" ]; then echo "compute processes: $(echo "$p" | tr '\n' ';')"
    elif [ "${m:-0}" -gt "$CAMPAIGN_MEM_MIB" ]; then echo "memory used: $m MiB"
    fi
}

gpu_free() {   # 0 = free; waits and retries; 3 = gave up
    t=1
    while :; do
        why=$(gpu_busy)
        [ -z "$why" ] && return 0
        say "GPU busy ($why), try $t of $CAMPAIGN_WAIT_TRIES" | tee -a "$CAMPAIGN_OUT/busy.log"
        [ "$t" -ge "$CAMPAIGN_WAIT_TRIES" ] && return 3
        t=$((t + 1)); sleep "$CAMPAIGN_WAIT_S"
    done
}

# ------------------------------------------------------------- replicates
rotate() {   # $1 rep, then arms: prints the arms rotated by rep (R5)
    r=$1; shift; n=$#; k=$((r % n)); i=0; out=""
    for a in "$@"; do [ "$i" -ge "$k" ] && out="$out $a"; i=$((i + 1)); done
    i=0
    for a in "$@"; do [ "$i" -lt "$k" ] && out="$out $a"; i=$((i + 1)); done
    echo $out
}

banner_ok() {   # $1 log, $2 expected: "cpu", or regexes separated by ';'
    case "$2" in
        cpu) ! grep -qE "^(CUDA: ready|OCL: gotowy)" "$1" ;;
        *)  rest=$2
            while [ -n "$rest" ]; do
                re=${rest%%;*}
                grep -qE "$re" "$1" || return 1
                [ "$rest" = "$re" ] && break
                rest=${rest#*;}
            done ;;
    esac
}

done_already() { grep -q "^$SESSION,$EXP,$1,$2,[^,]*,[^,]*,[^,]*,[^,]*,ok," "$CSV"; }

# run_rep <arm> <rep> <order> <gpu 0|1> <banner> <sanity fn> <command...>
#   0 ok, 3 gave up on a busy GPU, 4 rejected twice.
# The sanity function gets the log and the wall time and prints
# "<metric> <value>" when the run did its work, or a reason and returns 1.
run_rep() {
    arm=$1 rep=$2 order=$3 gpu=$4 banner=$5 sanity=$6; shift 6
    done_already "$arm" "$rep" && return 0
    for try in 1 2; do
        if [ "$gpu" = 1 ]; then gpu_free || return 3; fi
        log="$RUNS/${arm}_r${rep}$([ "$try" = 2 ] && echo _try2).log"
        started=$(date -Is)
        { header; echo "# arm: $arm"; echo "# rep: $rep"; echo "# command: $*"; } > "$log"
        t0=$(date +%s%N)
        "$@" >> "$log" 2>&1 </dev/null
        rc=$?
        t1=$(date +%s%N)
        wall=$(awk "BEGIN{printf \"%.4f\", ($t1 - $t0) / 1e9}")
        reason=""
        [ "$rc" = 0 ] || reason="exit code $rc"
        [ -z "$reason" ] && ! banner_ok "$log" "$banner" && reason="banner does not match: $banner"
        if [ -z "$reason" ]; then
            m=$($sanity "$log" "$wall") || reason="sanity: $m"
        fi
        if [ -z "$reason" ] && [ "$gpu" = 1 ]; then
            why=$(gpu_busy); [ -n "$why" ] && reason="GPU busy after the run: $why"
        fi
        if [ -z "$reason" ]; then
            echo "$SESSION,$EXP,$arm,$rep,$order,$wall,${m% *},${m##* },ok,$started" >> "$CSV"
            return 0
        fi
        say "$arm rep $rep try $try rejected: $reason"
        r=$(echo "$reason" | tr ',\n' ';;')
        echo "$SESSION,$EXP,$arm,$rep,$order,$wall,,,rejected: $r,$started" >> "$CSV"
        echo "$SESSION,$EXP,$arm,$rep,$try,$wall,$r,$log" >> "$CAMPAIGN_OUT/rejected.csv"
    done
    return 4
}

# run_arms <reps> <arm spec function>: warm-up then interleaved replicates.
# The spec function is called as "<fn> <arm> <rep> <order>" and must call
# run_rep. Shell functions share variables, so the loop's own start with _. Returns 0 when every arm has every replicate.
run_arms() {
    _reps=$1 _fn=$2; shift 2
    _st=0 _order=1
    for _a in "$@"; do $_fn "$_a" 0 "$_order" || _st=$?; _order=$((_order + 1)); done
    _r=1
    while [ "$_r" -le "$_reps" ]; do
        _order=1
        for _a in $(rotate "$_r" "$@"); do
            $_fn "$_a" "$_r" "$_order"; _s=$?
            [ "$_s" = 0 ] || _st=$_s
            [ "$_s" = 3 ] && return 3      # a busy GPU stays busy; resume later
            _order=$((_order + 1))
        done
        _r=$((_r + 1))
    done
    return $_st
}
