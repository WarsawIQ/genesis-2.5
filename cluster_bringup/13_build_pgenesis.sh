#!/bin/sh
# Build PGENESIS (pgenesis/bin/Linux/nxpgenesis) with MPICH, in the order
# cluster_bringup/70_pgenesis_build_status.md found to work: a CPU-only GENESIS
# build and nxinstall, the CPU hines library aliased as hineslib_cpu.o (the
# PGENESIS link pulls in no CUDA runtime), then PGENESIS. Run it before
# 10_build.sh, which must come last so it leaves no CUDA objects in genesis/lib.
#
# Needs MPICH (MPICH_BIN in env.sh), GCC, flex, bison, ncurses.
set -eu
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
ROOT=$GENESIS_ROOT
STUB="$ROOT/locallib/libfl.a"
if [ ! -f "$STUB" ]; then
  mkdir -p "$ROOT/locallib"
  printf 'int yywrap(void){return 1;}\n' > "$ROOT/locallib/yywrap.c"
  gcc -c "$ROOT/locallib/yywrap.c" -o "$ROOT/locallib/yywrap.o"
  ar rcs "$STUB" "$ROOT/locallib/yywrap.o"
fi
export PATH="$MPICH_BIN:$PATH"
unset MPI_LIB   # the mpich module exports a bare directory the Makefile splices into the link line
command -v mpicc >/dev/null || { echo "no mpicc in $MPICH_BIN" >&2; exit 1; }

cd "$ROOT/genesis/src"
make clean >/dev/null 2>&1 || true
rm -f hines/cuda/*.o hines/opencl/*.o hines/hineslib.o
make LEXLIB="$STUB" EXTRALIBS="sprng/lib/liblfg.a -lncurses -ltinfo" nxgenesis
make LEXLIB="$STUB" EXTRALIBS="sprng/lib/liblfg.a -lncurses -ltinfo" nxinstall
cp -f "$ROOT/genesis/lib/hineslib.o" "$ROOT/genesis/lib/hineslib_cpu.o"

cd "$ROOT/pgenesis"
# nxinstall reports some "Error 126 (ignored)" lines from install helpers and
# still produces a working binary (70_pgenesis_build_status.md).
make LEXLIB="$STUB" nxinstall || true
[ -x bin/Linux/nxpgenesis ] || { echo "PGENESIS build failed: no bin/Linux/nxpgenesis" >&2; exit 1; }
echo "== done =="
ls -la bin/Linux/nxpgenesis
