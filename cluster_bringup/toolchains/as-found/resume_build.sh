#!/bin/bash
# Resume the NEURON GPU build in place.
#
# NVHPC 24.11 got past the nocmodl segfault that 25.3 produced (zero segfaults in
# this log). What stopped it is a parallel-make race on nrnconf.h: both the source
# and its copy exist and are identical, so the copy simply lost a race. Re-running
# make picks up where it stopped; the serial pass first settles the generated
# headers before parallel compilation resumes.
set -eu
NVHPC_ROOT="$HOME/opt/nvhpc24/Linux_x86_64/24.11"
export PATH="$HOME/opt/miniforge/bin:$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"
cd "$HOME/nrn_src/build-gpu"

make -j1 >> make.log 2>&1 || true
make -j"$(nproc)" >> make.log 2>&1 || { echo "BUILD FAILED"; grep -iE "error|segmentation" make.log | tail -15; exit 1; }
make install >> install.log 2>&1
echo "=== installed ==="
ls "$HOME/opt/nrn-gpu/bin" 2>/dev/null | head
