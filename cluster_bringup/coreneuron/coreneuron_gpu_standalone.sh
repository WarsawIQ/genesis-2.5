#!/bin/bash
# CoreNEURON on the GPU without a working NVHPC-built NEURON.
#
# Building NEURON with NVHPC gives binaries that segfault: both code generators,
# the Python module, and the interpreter on a single passive soma. CoreNEURON
# itself built fine, and it does not need NEURON at run time -- NEURON writes the
# model out, special-core reads those files and simulates them alone. So the
# interpreter stays on the working pip build (GCC) and only CoreNEURON goes
# through NVHPC, which is the part written for it.
#
# init.hoc builds the model and then runs it, ending with pc.done(), which stops
# the process before anything after load_file() executes. A copy with the run
# and teardown calls commented out builds the model and stops there, which is
# all nrncore_write needs.
#
# Needs toolchains/fetch_modeldb_83319.sh, toolchains/30_neuron_gpu.sh and
# build_mechanisms.sh to have run. special-core comes from $COBAHH_GPU_MECH,
# the build linked with -lstdc++fs; the earlier build without it does not load,
# and this script used to point at that one.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/cluster_bringup/env.sh"
SRC="$MODELDB_DIR/destexhe_benchmarks"
W="$RUN_DIR/cobahh_dumponly"
DUMP="$RUN_DIR/cobahh_coredat"
CORE="$COBAHH_GPU_MECH/x86_64/special-core"
V="$NVHPC_ROOT"
mkdir -p "$RUN_DIR"

[ -x "$CORE" ] || { echo "no special-core at $CORE" >&2; exit 1; }

echo "== 1. model-only copy of the benchmark =="
rm -rf "$W"; cp -a "$SRC" "$W"
cd "$W/NEURON/cobahh" || exit 1
sed -i -e '27s/^prun()/\/\/ prun()/' \
       -e '40s/^{pc.runworker()}/\/\/ {pc.runworker()}/' \
       -e '43s/^collect_results()/\/\/ collect_results()/' \
       -e '47s/^{pc.done()}/\/\/ {pc.done()}/' \
       -e '52s/^output_results()/\/\/ output_results()/' init.hoc
grep -nE "^// (prun|collect_results|output_results)|^// \{pc" init.hoc

echo
echo "== 2. dumping the model from the working NEURON (pip, GCC) =="
rm -rf "$DUMP"; mkdir -p "$DUMP"
cat > dump_core.py <<'PY'
import os
from neuron import h
h.load_file("stdrun.hoc")
h.cvode.cache_efficient(1)
h("mosinit=0")
h.load_file("init.hoc")
pc = h.ParallelContext()
h.finitialize(-70)
pc.nrncore_write(os.environ["DUMP"])
print("DUMP_OK")
PY
DUMP="$DUMP" timeout 1800 "$NRN_PYTHON" dump_core.py > dump.log 2>&1
if ! grep -q DUMP_OK dump.log; then
    echo "dump FAILED"; tail -12 dump.log; exit 1
fi
echo "files written: $(ls "$DUMP" | wc -l)"

echo
echo "== 3. CoreNEURON standalone on the GPU =="
export LD_LIBRARY_PATH="$NRN_GPU_BUILD/lib:$V/compilers/lib:$V/cuda/12.6/lib64:${LD_LIBRARY_PATH:-}"
nvidia-smi --query-gpu=name,memory.used --format=csv,noheader
for r in $(seq 1 "${REPS:-3}"); do   # REPS=0 only prepares the dump
    S=$(date +%s%N)
    timeout 1800 "$CORE" --datpath "$DUMP" --gpu --tstop 5000 --dt 0.05 > "$RUN_DIR/cn_gpu_run_$r.log" 2>&1
    RC=$?
    E=$(date +%s%N)
    awk "BEGIN{printf \"  gpu rep $r wall=%.2f s rc=$RC\n\", ($E-$S)/1e9}"
    grep -iE "Solver Time|Setup Time" "$RUN_DIR/cn_gpu_run_$r.log" | head -2
    [ "$RC" -eq 0 ] || { echo "--- failure ---"; tail -12 "$RUN_DIR/cn_gpu_run_$r.log"; break; }
done
