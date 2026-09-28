#!/bin/bash
# Finish the install with the generators the install step expects, then put the
# working ones back.
#
# make completed; make install did not. CMake rewrites RPATH on the binaries it
# installs and refuses when the RPATH is not the one it wrote, which is exactly
# the case for the GCC-built nmodl substituted into the tree. Install only
# copies files, so the order that works is: let nvc++ rebuild its own generators
# for the install to consume, install, then overwrite the installed generators
# with the GCC builds that actually run.
set -eu
NVHPC_ROOT="$HOME/opt/nvhpc24/Linux_x86_64/24.11"
MF="$HOME/opt/miniforge"
SRC="$HOME/nrn_src"; GPU="$SRC/build-gpu"; PREFIX="$HOME/opt/nrn-gpu"
GCC_NOCMODL="$SRC/build-hosttools/bin/nocmodl"
GCC_NMODL="$SRC/build-hostnmodl/bin/nmodl"

for f in "$GCC_NOCMODL" "$GCC_NMODL"; do
    [ -x "$f" ] || { echo "missing $f"; exit 1; }
done

export PATH="$MF/bin:$NVHPC_ROOT/compilers/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_ROOT/compilers/lib:${LD_LIBRARY_PATH:-}"
cd "$GPU"

# Let nvc++ produce its own generators again so the RPATH matches what install
# expects. They segfault when run, but nothing runs them from here on: all the
# .cpp translation is already done.
# The substituted binaries are newer than their sources, so make considers them
# up to date and will not rebuild. Remove them first.
rm -f "$GPU/bin/nmodl" "$GPU/bin/nocmodl"
make -j"$(nproc)" nmodl nocmodl >> make.log 2>&1 || true
ls -la "$GPU/bin/nmodl" "$GPU/bin/nocmodl" 2>/dev/null || true
make install >> install.log 2>&1 || { echo "INSTALL STILL FAILING"; tail -20 install.log; exit 1; }

# Now restore the generators that work, for when nrnivmodl builds model
# mechanisms later.
for pair in "$GCC_NOCMODL:$PREFIX/bin/nocmodl" "$GCC_NMODL:$PREFIX/bin/nmodl"; do
    s="${pair%%:*}"; d="${pair##*:}"
    [ -e "$d" ] && cp -f "$s" "$d" && echo "installed working generator -> $d"
done

echo "=== installed ==="
ls "$PREFIX/bin" | tr '\n' ' '; echo
"$PREFIX/bin/nmodl" --version 2>&1 | head -1 || true
"$PREFIX/bin/nrniv" -c 'print "hoc ok"' 2>&1 | tail -1 || true
