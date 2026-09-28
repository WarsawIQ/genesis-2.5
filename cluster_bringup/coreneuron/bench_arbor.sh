#!/bin/bash
# Arbor on CPU and GPU, same model and node as the GENESIS and NEURON arms.
#
# This is the GPU-to-GPU comparison the paper needs: CoreNEURON's GPU path is
# unreachable on this cluster, but Arbor targets CUDA directly and builds here.
#
# The context is printed for every run. Arbor reports has_gpu from the build,
# not from the context in use, so the arm has to be identified by which context
# was constructed -- the same silent-substitution risk CoreNEURON had.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
sh "$GENESIS_ROOT/cluster_bringup/coreneuron/arbor_check.sh" || exit 1
P="$ARBOR_PY"
export PYTHONPATH="$P"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}"
PY="$ARBOR_PYTHON"
N=${N:-10000}
K=${K:-5000}
REPS=${REPS:-3}
cd "$GENESIS_ROOT/cluster_bringup/coreneuron" || exit 1

echo "== Arbor N=$N NCOMP=16 K=$K on $(hostname) =="
nvidia-smi --query-gpu=name,memory.used --format=csv,noheader

for arm in cpu gpu; do
    g=0; [ "$arm" = gpu ] && g=1
    for r in $(seq 1 "$REPS"); do
        out=$(USE_GPU=$g timeout 3600 "$PY" hh_multicomp_arbor.py "$N" "$K" 2>&1)
        w=$(echo "$out" | sed -n 's/^RESULT_WALL_S=//p')
        b=$(echo "$out" | sed -n 's/^RESULT_BUILD_S=//p')
        s=$(echo "$out" | sed -n 's/^RESULT_RUN_S=//p')
        c=$(echo "$out" | sed -n 's/^RESULT_CTX=//p')
        if [ -z "$w" ]; then
            echo "  arbor-$arm rep $r FAILED"; echo "$out" | tail -5; break
        fi
        echo "  arbor-$arm rep $r wall=${w}s build=${b}s run=${s}s ctx=${c}"
    done
done
