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
#   rejected_<node>.csv         every rejected run with its reason
#   runs/<session>/<arm>_r<rep>[_try2].log   full output of each run
#   <exp>_<node>.open           the session to resume, while one is unfinished
#
# Environment (see cluster_bringup/campaign/README.md):
#   CAMPAIGN_TAG   tag HEAD must be at (default v2.6.0-rc2)
#   CAMPAIGN_DRY   1 = untagged or dirty tree allowed, data go to campaign_dry/
#   CAMPAIGN_WAIT_S, CAMPAIGN_WAIT_TRIES   busy-GPU retry (600 s, 6 tries)
#   NVIDIA_SMI     nvidia-smi to call (the tests substitute a stub)

GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
CAMPAIGN_TAG=${CAMPAIGN_TAG:-v2.6.0-rc2}
CAMPAIGN_DRY=${CAMPAIGN_DRY:-0}
CAMPAIGN_WAIT_S=${CAMPAIGN_WAIT_S:-600}
CAMPAIGN_WAIT_TRIES=${CAMPAIGN_WAIT_TRIES:-6}
CAMPAIGN_MEM_MIB=${CAMPAIGN_MEM_MIB:-100}   # memory in use on an idle card, at most
NVSMI=${NVIDIA_SMI:-nvidia-smi}
NODE=${CAMPAIGN_NODE:-$(hostname -s)}

say() { echo "[$(date +%H:%M:%S)] $*"; }

has_gpu() { command -v "${NVSMI%% *}" >/dev/null 2>&1 && $NVSMI -L >/dev/null 2>&1; }

# Every run is bound to the GPU's own NUMA node, CPU arms included, so both arms
# of a speedup use the same socket and memory. Unbound, a single-threaded run
# landed on either socket of inf02, whose two sockets differ by ~17% under load
# (night 1, 2026-10-03: CPU arms bimodal, RSD 8-11%; numa_check.sh measured
# 24.6-25.0 s on one socket and 28.6-29.1 s on the other, and 28.6-28.8 s bound
# to the GPU's node). CAMPAIGN_NUMA: auto (the GPU's node), a node number, or
# off. Where no node can be found (one socket, no GPU) nothing is bound.
numa_node() {
    case "${CAMPAIGN_NUMA:-auto}" in
        off) return 0 ;;
        auto) ;;
        *) echo "$CAMPAIGN_NUMA"; return 0 ;;
    esac
    has_gpu || return 0
    command -v numactl >/dev/null 2>&1 || return 0
    _bus=$($NVSMI --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -1 \
           | tr 'A-F' 'a-f' | sed 's/^0000\(....:\)/\1/')
    _f=/sys/bus/pci/devices/$_bus/numa_node
    [ -r "$_f" ] || _f=/sys/bus/pci/devices/0000$(echo "$_bus" | sed 's/^[0-9a-f]\{4\}//')/numa_node
    [ -r "$_f" ] || return 0
    _n=$(cat "$_f")
    [ "$_n" -ge 0 ] 2>/dev/null && echo "$_n"
}

# ------------------------------------------------------------------ header
header() {   # the run header of data-model.md, as '# key: value' lines
    echo "# experiment: $EXP"
    echo "# session: $SESSION"
    echo "# commit: $COMMIT"
    echo "# describe: $DESCRIBE"
    echo "# dirty: $DIRTY"
    echo "# build_generated_changed: $GENCHANGED"
    echo "# node: $NODE"
    echo "# cpu: $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
    echo "# governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
    echo "# loadavg: $(cut -d' ' -f1-3 /proc/loadavg)"
    echo "# numa_bind: ${NUMA_NODE:-none}"
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
    # The build rewrites some tracked generated files (build_generated.txt);
    # they are counted apart, and any other change makes the tree dirty.
    _gen=$(grep -v '^#' cluster_bringup/campaign/build_generated.txt | sed 's/^/:(exclude)/')
    DIRTY=$(git status --porcelain --untracked-files=no -- . $_gen | wc -l | tr -d ' ')
    GENCHANGED=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
    GENCHANGED=$((GENCHANGED - DIRTY))
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
    NUMA_NODE=$(numa_node)
    NUMA_PREFIX=""
    [ -n "$NUMA_NODE" ] && NUMA_PREFIX="numactl --cpunodebind=$NUMA_NODE --membind=$NUMA_NODE"
    CSV="$CAMPAIGN_OUT/${EXP}_${SESSION}.csv"
    RUNS="$CAMPAIGN_OUT/runs/$SESSION"
    mkdir -p "$RUNS"
    if [ ! -f "$CSV" ]; then
        { header; echo "session,experiment,arm,rep,order,wall_s,metric,metric_value,status,started"; } > "$CSV"
    else
        echo "# resumed: $(date -Is)" >> "$CSV"
    fi
    [ -f "$CAMPAIGN_OUT/rejected_$NODE.csv" ] || \
        echo "session,experiment,arm,rep,try,wall_s,reason,log" > "$CAMPAIGN_OUT/rejected_$NODE.csv"
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
        say "GPU busy ($why), try $t of $CAMPAIGN_WAIT_TRIES" | tee -a "$CAMPAIGN_OUT/busy_$NODE.log"
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
        { header; echo "# arm: $arm"; echo "# rep: $rep"; echo "# command: $([ "${NUMA_SKIP:-0}" = 1 ] || echo "$NUMA_PREFIX") $*"; } > "$log"
        t0=$(date +%s%N)
        _pre=$NUMA_PREFIX
        [ "${NUMA_SKIP:-0}" = 1 ] && _pre=""   # multi-rank MPI spans sockets on purpose
        $_pre "$@" >> "$log" 2>&1 </dev/null
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
        echo "$SESSION,$EXP,$arm,$rep,$try,$wall,$r,$log" >> "$CAMPAIGN_OUT/rejected_$NODE.csv"
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

# ------------------------------------------------------------- helpers
# VAnet2 needs the default schedule, so it cannot run under -nosimrc: each arm
# gets a scratch copy of the model with its own .simrc (as reproduce/stages/50).
vanet2_workdir() {   # $1 directory to create
    rm -rf "$1"; mkdir -p "$1"
    cp "$GENESIS_ROOT"/genesis/Scripts/VAnet2/*.g "$GENESIS_ROOT"/genesis/Scripts/VAnet2/*.p "$1"/
    printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
        "$GENESIS_ROOT" "$GENESIS_ROOT" "$GENESIS_ROOT" "$1" "$GENESIS_ROOT" > "$1/.simrc"
}

# The banners each kind of arm must print (checked by run_rep).
BANNER_CPU=cpu
BANNER_CUDA32='^CUDA: ready \(.* fp32 kernels\);^CUDA: graph dispatch: tree loop on, per-step off'
BANNER_CUDA64='^CUDA: ready \(.* fp64 kernels\);^CUDA: graph dispatch: tree loop on, per-step off'
BANNER_OCL32='^OCL: gotowy \(.* kernele fp32\)'
BANNER_OCL64='^OCL: gotowy \(.* kernele fp64\)'
BANNER_ANY='.'          # another simulator: nothing of ours to check

cuda_env() {   # the CUDA runtime on the library path for GPU binaries
    [ -d "${CUDA_HOME:-}/lib64" ] && LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" \
        && export LD_LIBRARY_PATH
    # Above 20000 compartments the batched tree solver would otherwise decline
    # the model and fall back to per-step dispatch, a different code path.
    export GENESIS_OCL_TREE_MAX_NCOMPTS=0
}

# tree_rep <arm> <rep> <order> <backend> <N> <K> <NCOMP> [VAR=value ...]
# One run of the dendritic-tree benchmark (hh_multicompartment_createmap.g),
# N neurons of NCOMP compartments for K steps, in the paper's arm definitions:
# cpu = the fp64 CPU solver (chanmode 1, CPU-only binary); cuda32, cuda64 =
# the CUDA tree kernel batched over the whole run; ocl32, ocl64 = the same with
# OpenCL. Extra VAR=value pairs go into the run's environment (the mixed-tree
# switches of E7, for instance). NCOMP may be "A,B" for a mixed population.
tree_rep() {
    _arm=$1 _rep=$2 _ord=$3 _be=$4 _n=$5 _k=$6 _nc=$7; shift 7
    EXPECT_N=$_n EXPECT_STEPS=$_k EXPECT_NCOMP=$_nc
    _s=genesis/Scripts/benchmark/hh_multicompartment_createmap.g
    case "$_be" in
        cpu)    run_rep "$_arm" "$_rep" "$_ord" 0 "$BANNER_CPU" sanity_tree \
                    env GENESIS_BENCH_CHANMODE=1 GENESIS_BENCH_NCOMP="${_nc%%,*}" "$@" \
                    timeout 7200 ./genesis/src/nxgenesis_nocl -nosimrc -notty -batch "$_s" "$_n" "$_k" ;;
        cuda32|cuda64)
                _p=fp32; _b=$BANNER_CUDA32
                [ "$_be" = cuda64 ] && _p=fp64 && _b=$BANNER_CUDA64
                run_rep "$_arm" "$_rep" "$_ord" 1 "$_b" sanity_tree \
                    env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP="${_nc%%,*}" \
                    GENESIS_CUDA_MULTILOOP=$((_k + 10)) GENESIS_GPU_PRECISION=$_p "$@" \
                    timeout 7200 ./genesis/src/nxgenesis -nosimrc -notty -batch "$_s" "$_n" "$_k" ;;
        ocl32|ocl64)
                _p=fp32; _b=$BANNER_OCL32
                [ "$_be" = ocl64 ] && _p=fp64 && _b=$BANNER_OCL64
                run_rep "$_arm" "$_rep" "$_ord" 1 "$_b" sanity_tree \
                    env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP="${_nc%%,*}" \
                    GENESIS_OCL_MULTILOOP=$((_k + 10)) GENESIS_GPU_PRECISION=$_p "$@" \
                    timeout 7200 "${OCL_BIN:-./genesis/src/nxgenesis_ocl}" -nosimrc -notty -batch "$_s" "$_n" "$_k" ;;
    esac
}

# need <path> <what makes it>: refuse a stage whose inputs are missing
need() { [ -e "$1" ] || { echo "REFUSED: missing $1 ($2)" >&2; exit 2; }; }

# A binary with no native code for the card either fails to launch or is
# JIT-compiled from PTX and runs slow while still being timed as GPU (an A100
# once measured 278.9 s against 4.6 s that way). Refuse before timing anything.
need_sass() {   # $1 binary
    has_gpu || { echo "REFUSED: no GPU on $NODE" >&2; exit 2; }
    _cc=sm_$($NVSMI --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '. ')
    [ -x "$CUDA_HOME/bin/cuobjdump" ] || return 0
    "$CUDA_HOME/bin/cuobjdump" --list-elf "$1" 2>/dev/null | grep -q "$_cc" \
        || { echo "REFUSED: $1 has no $_cc code for this card" >&2; exit 2; }
}

# arbor_rep <arm> <rep> <order> <N> <K>: Arbor 0.10.0 on the GPU, the same
# dendritic-tree model (cluster_bringup/coreneuron/hh_multicomp_arbor.py).
arbor_rep() {
    SANITY_RE='^RESULT_WALL_S=' SANITY_METRIC=arbor_wall_s
    run_rep "$1" "$2" "$3" 1 "$BANNER_ANY" sanity_grep \
        env -C "$GENESIS_ROOT/cluster_bringup/coreneuron" USE_GPU=1 PYTHONPATH="$ARBOR_PY" \
        LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
        timeout 3600 "$ARBOR_PYTHON" hh_multicomp_arbor.py "$4" "$5"
}
