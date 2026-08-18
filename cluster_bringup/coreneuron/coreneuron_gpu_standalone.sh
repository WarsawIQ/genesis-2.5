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
set -u
SRC="$HOME/coreneuron_cmp/destexhe_benchmarks"
W="$HOME/cobahh_dumponly"
DUMP="$HOME/cobahh_coredat"
CORE="$SRC/NEURON/cobahh/x86_64_gpu/x86_64/special-core"
V="$HOME/opt/nvhpc24/Linux_x86_64/24.11"

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
DUMP="$DUMP" timeout 1800 python3.12 dump_core.py > dump.log 2>&1
if ! grep -q DUMP_OK dump.log; then
    echo "dump FAILED"; tail -12 dump.log; exit 1
fi
echo "files written: $(ls "$DUMP" | wc -l)"

echo
echo "== 3. CoreNEURON standalone on the GPU =="
export LD_LIBRARY_PATH="$HOME/nrn_src/build-gpu/lib:$V/compilers/lib:$V/cuda/12.6/lib64:${LD_LIBRARY_PATH:-}"
nvidia-smi --query-gpu=name,memory.used --format=csv,noheader
for r in 1 2 3; do
    S=$(date +%s%N)
    timeout 1800 "$CORE" --datpath "$DUMP" --gpu --tstop 5000 --dt 0.05 > "$HOME/cn_gpu_run_$r.log" 2>&1
    RC=$?
    E=$(date +%s%N)
    awk "BEGIN{printf \"  gpu rep $r wall=%.2f s rc=$RC\n\", ($E-$S)/1e9}"
    grep -iE "Solver Time|Setup Time" "$HOME/cn_gpu_run_$r.log" | head -2
    [ "$RC" -eq 0 ] || { echo "--- failure ---"; tail -12 "$HOME/cn_gpu_run_$r.log"; break; }
done
