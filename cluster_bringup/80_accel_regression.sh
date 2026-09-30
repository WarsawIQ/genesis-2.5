#!/bin/sh
# Characterisation test for the OpenCL/CUDA accelerator backends.
#
# This is NOT a correctness test against an analytic result -- it pins the
# behaviour the backends have *right now*, so that a refactor which is supposed
# to move state around without changing any arithmetic can be shown to have done
# exactly that. The strong criterion is byte-identity of the recorded values
# before and after; a tolerance against the CPU arm would be far too loose to
# catch an indexing slip.
#
# Only deterministic outputs are recorded. RESULT_T_TOTAL / RESULT_T_PER_STEP
# are wall-clock timings and are deliberately excluded -- including them would
# make the golden file fail on every run for reasons that have nothing to do
# with correctness.
#
# Usage:
#   sh 80_accel_regression.sh record   # write cluster_bringup/accel_regression_golden.txt
#   sh 80_accel_regression.sh check    # regenerate and diff against it
#   sh 80_accel_regression.sh fp64     # GPU in double: every value within 1e-10 V
#                                      # of the CPU solver (no golden file)
#
# record and check run the GPU in the default precision (fp32) whatever
# GENESIS_GPU_PRECISION says, since that is what the golden files pin. Every
# mode also checks that each GPU run reported the precision it was meant to
# use; a run that silently fell back to the other one fails.
#
# Must run on a node with the GPU the golden file was recorded on: the fp32
# kernels are not bit-identical across different devices, so a golden recorded
# on the A40 will not match the A100. The device is recorded in the file header
# and check refuses to compare across devices.
#
# Prepared by Karol Chlasta (karol@chlasta.pl).
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT"

MODE=${1:-check}
# Overridable so the same harness can hold separate baselines per backend: the
# fp32 OpenCL and CUDA kernels are not bit-identical to each other, so each
# needs its own golden (as does each device -- see the check below).
GOLDEN=${ACCEL_GOLDEN:-"$HERE/accel_regression_golden.txt"}
OUT=$(mktemp)
BANNERS=$(mktemp)
trap 'rm -f "$OUT" "$BANNERS"' EXIT

if [ "$MODE" = fp64 ]; then
    export GENESIS_GPU_PRECISION=fp64; WANT=fp64
else
    unset GENESIS_GPU_PRECISION;       WANT=fp32
fi

BIN_CPU=./genesis/src/nxgenesis_nocl
BIN_GPU=./genesis/src/nxgenesis
BENCH=genesis/Scripts/benchmark
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

for b in "$BIN_CPU" "$BIN_GPU"; do
    [ -x "$b" ] || { echo "ERROR: missing $b -- build first" >&2; exit 1; }
done

DEVICE=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
[ -n "$DEVICE" ] || DEVICE="no-gpu"

# run <label> <binary> <env-assignments-or-"-"> <script> [args...]
# Records every RESULT_* line except the timing ones, plus NEURONS_AGREE.
run() {
    label=$1; bin=$2; envs=$3; shift 3
    if [ "$envs" = "-" ]; then
        out=$(timeout 600 "$bin" -nosimrc -notty -batch "$@" </dev/null 2>&1)
    else
        out=$(timeout 600 env $envs "$bin" -nosimrc -notty -batch "$@" </dev/null 2>&1)
    fi
    # The backend's start-up line names the kernel precision (CUDA: "... fp32
    # kernels)", OpenCL: "kernele fp32"). Kept apart from the recorded values
    # so the golden files do not change.
    echo "$label $(echo "$out" | grep -o -E '(fp32|fp64) kernels|kernele (fp32|fp64)' \
        | grep -o -E 'fp32|fp64' | head -1)" >> "$BANNERS"
    echo "$out" \
      | grep -E "^(RESULT_[A-Z_]+=|NEURONS_AGREE:)" \
      | grep -vE "^RESULT_T_" \
      | sed "s|^|$label\||"
}

{
    echo "# accelerator regression golden"
    echo "# device: $DEVICE"

    run ap_cpu     "$BIN_CPU" -                        $BENCH/hh1952_ap_verify.g 8 200
    run ap_gpu     "$BIN_GPU" GENESIS_CUDA_MULTILOOP=210 $BENCH/hh1952_ap_verify.g 8 200

    run multi_cpu  "$BIN_CPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=1" \
                   $BENCH/hh_multicompartment_benchmark.g
    run multi_gpu  "$BIN_GPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=4" \
                   $BENCH/hh_multicompartment_benchmark.g

    run branch_cpu "$BIN_CPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=1" \
                   $BENCH/hh_branching_multicompartment_benchmark.g
    run branch_gpu "$BIN_GPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=4" \
                   $BENCH/hh_branching_multicompartment_benchmark.g

    # fp64 compares the GPU with the CPU in the same hsolve mode. The *_cpu
    # arms above run chanmode 1, whose results differ from chanmode 4's by up
    # to 4e-10 V on the CPU alone (measured 2026-09-30), which is a property of
    # the solver modes, not of GPU precision.
    if [ "$MODE" = fp64 ]; then
        run multi_cpu4  "$BIN_CPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=4" \
                        $BENCH/hh_multicompartment_benchmark.g
        run branch_cpu4 "$BIN_CPU" "GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=4" \
                        $BENCH/hh_branching_multicompartment_benchmark.g
    fi
} > "$OUT" 2>/dev/null

# VAnet2 (Vogels-Abbott) is the correctness anchor for a real network model.
#
# Its GPU arm is excluded from the default run: since SYN2_OP became supported
# the accelerator no longer declines this model, so the arm actually executes --
# and with one solver per cell it needs hours, not the seconds the rest of this
# harness takes. Set ACCEL_VANET2_GPU=1 to include it once cross-solver dispatch
# is cheap enough for that to be reasonable.
VA=$RUN_DIR/vanet2_regression
VA_ARMS="cpu"
[ "${ACCEL_VANET2_GPU:-0}" = "1" ] && VA_ARMS="cpu gpu"
if [ -d genesis/Scripts/VAnet2 ]; then
    for arm in $VA_ARMS; do
        rm -rf "$VA-$arm"; mkdir -p "$VA-$arm"
        cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p "$VA-$arm/" 2>/dev/null
        bin=$BIN_CPU; [ "$arm" = gpu ] && bin=$BIN_GPU
        # VAnet2 cannot use -nosimrc: it needs the default simulation schedule.
        # Without `schedule` nothing is attached to the clocks, `step` returns
        # immediately and the run silently produces no output at all.
        printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
            "$ROOT" "$ROOT" "$ROOT" "$RUN_DIR" "$ROOT" > "$VA-$arm/.simrc"
        ( cd "$VA-$arm" && timeout 900 "$ROOT/$bin" -notty -batch VAnet2-batch.g \
            > out.log 2>&1 )
        if [ -s "$VA-$arm/Vm_out_1000.txt" ]; then
            echo "vanet2_$arm|vm_md5=$(md5sum < "$VA-$arm/Vm_out_1000.txt" | cut -d' ' -f1)" >> "$OUT"
            echo "vanet2_$arm|vm_lines=$(wc -l < "$VA-$arm/Vm_out_1000.txt")" >> "$OUT"
        else
            echo "vanet2_$arm|vm_md5=MISSING" >> "$OUT"
        fi
    done
    if [ "${ACCEL_VANET2_GPU:-0}" = "1" ]; then
        if grep -qi "acceleration disabled" "$VA-gpu/out.log" 2>/dev/null; then
            echo "vanet2_gpu|guard=fired" >> "$OUT"
        else
            echo "vanet2_gpu|guard=not-fired" >> "$OUT"
        fi
    fi
fi

# Every GPU arm must have reported the precision this mode asked for.
bad=$(awk -v want="$WANT" '$1 ~ /_gpu$/ && $2 != want {print $1 " reported [" $2 "]"}' "$BANNERS")
if [ -n "$bad" ]; then
    echo "FAIL: GPU runs not in $WANT:" >&2
    echo "$bad" >&2
    exit 1
fi

case "$MODE" in
  fp64)
    # Pair each GPU value with the CPU value of the same benchmark and key,
    # taking the chanmode-4 CPU run where there is one.
    awk -F'|' -v tol=1e-10 '
        /^#/ || !/RESULT_V/ { next }
        { split($1, a, "_"); arm = a[length(a)]; bench = substr($1, 1, length($1) - length(arm) - 1)
          split($2, kv, "="); v[bench "|" kv[1] "|" arm] = kv[2] + 0; keys[bench "|" kv[1]] = 1 }
        END {
          fail = 0; n = 0
          for (k in keys) {
            c = ((k "|cpu4") in v) ? v[k "|cpu4"] : v[k "|cpu"]
            g = v[k "|gpu"]; d = g - c; if (d < 0) d = -d; n++
            printf "%-28s cpu %.10f  gpu %.10f  |diff| %.2e %s\n", k, c, g, d, (d <= tol ? "ok" : "OUTSIDE")
            if (d > tol) fail = 1
          }
          if (fail) { print "FAIL: fp64 GPU differs from the CPU by more than " tol " V"; exit 1 }
          printf "PASS: %d values within %s V of the CPU solver (fp64 kernels)\n", n, tol
        }' "$OUT"
    ;;
  record)
    cp "$OUT" "$GOLDEN"
    echo "recorded $(grep -c '|' "$GOLDEN") values on $DEVICE -> $GOLDEN"
    ;;
  check)
    [ -f "$GOLDEN" ] || { echo "ERROR: no golden file; run 'record' first" >&2; exit 1; }
    gdev=$(sed -n 's/^# device: //p' "$GOLDEN")
    if [ "$gdev" != "$DEVICE" ]; then
        echo "ERROR: golden recorded on '$gdev', running on '$DEVICE'." >&2
        echo "       fp32 kernels are not bit-identical across devices; re-record." >&2
        exit 1
    fi
    if diff -u "$GOLDEN" "$OUT"; then
        echo "PASS: $(grep -c '|' "$GOLDEN") values unchanged on $DEVICE"
    else
        echo "FAIL: accelerator output changed (diff above)" >&2
        exit 1
    fi
    ;;
  *)
    echo "usage: $0 [record|check|fp64]" >&2; exit 2
    ;;
esac
