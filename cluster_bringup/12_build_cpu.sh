#!/bin/sh
# Build the CPU-only GENESIS binary, nxgenesis_nocl, with no GPU toolkit at all.
#
# For the parts of the paper that need no GPU (the Hines-solver fixes, linear
# model construction, the spiking network on one CPU core) and for anyone
# without CUDA or OpenCL. 10_build.sh builds this binary too, but needs nvcc.
#
# Needs GCC, GNU make, flex, bison and ncurses. Builds a stub libfl when the
# system's flex ships without one (as on the UMCS cluster).
set -eu
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
ROOT=$GENESIS_ROOT
SRC="$ROOT/genesis/src"

STUB="$ROOT/locallib/libfl.a"
if [ ! -f "$STUB" ]; then
  mkdir -p "$ROOT/locallib"
  printf 'int yywrap(void){return 1;}\n' > "$ROOT/locallib/yywrap.c"
  gcc -c "$ROOT/locallib/yywrap.c" -o "$ROOT/locallib/yywrap.o"
  ar rcs "$STUB" "$ROOT/locallib/yywrap.o"
fi

cd "$SRC"
make clean >/dev/null 2>&1 || true
rm -f hines/cuda/*.o hines/opencl/*.o hines/hineslib.o
make LEXLIB="$STUB" EXTRALIBS="sprng/lib/liblfg.a -lncurses -ltinfo" nxgenesis
cp -f nxgenesis nxgenesis_nocl

# genesis/startup, as make install would create it (see 10_build.sh).
( cd startup && mkdir -p ../../startup \
  && cp -f $(sed -n 's/^OBJS = //p' Makefile) ../../startup/ )

echo "== done =="
ls -la nxgenesis_nocl
