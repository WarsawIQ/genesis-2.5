#!/bin/sh
# Build nxgenesis with the OpenCL backend on the current node (inf02=A40).
# Companion to 10_build.sh (CUDA) -- validates whether the hines_tree_eliminate
# kernel (GENESIS 2.5, 2026-07-25) works on this cluster's NVIDIA OpenCL ICD,
# not just the local AMD iGPU it was developed against.
#
# Toolchain notes for this cluster (RHEL 8.5.0 gcc, no CL/cl.h in /usr/include):
#   - libOpenCL.so IS in the standard system lib path (ldconfig -p shows
#     /lib64/libOpenCL.so, NVIDIA driver's ICD) -- no -L needed for linking.
#   - CL/cl.h is NOT in /usr/include, only under the CUDA toolkit's own
#     include tree. Using CPATH (a GCC env var, not threaded through the
#     Makefile's CFLAGS_IN composition at all) avoids the documented
#     CFLAGS-propagation-through-recursive-submake pitfall from the CUDA
#     build fixes.
#   - Fix 1 (libfl) reused as-is from 10_build.sh.
#
# Prepared by Karol Chlasta (karol@chlasta.pl).
set -eu
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SRC="$ROOT/genesis/src"

CUDA_HOME=$OPENCL_CUDA_HOME   # the CL headers come from the 13.0 toolkit
export CPATH="$CUDA_HOME/targets/x86_64-linux/include${CPATH:+:$CPATH}"
CC=${CC:-$(command -v gcc)}

STUB="$ROOT/locallib/libfl.a"
if [ ! -f "$STUB" ]; then
  mkdir -p "$ROOT/locallib"
  printf 'int yywrap(void){return 1;}\n' > "$ROOT/locallib/yywrap.c"
  gcc -c "$ROOT/locallib/yywrap.c" -o "$ROOT/locallib/yywrap.o"
  ar rcs "$STUB" "$ROOT/locallib/yywrap.o"
fi
EXTRALIBS="sprng/lib/liblfg.a -lncurses -ltinfo -lOpenCL"

echo "CPATH=$CPATH"
echo "CC=$CC"
echo "EXTRALIBS=$EXTRALIBS"

cd "$SRC"

echo "== [1/2] CPU reference build =="
make clean >/dev/null 2>&1
make LEXLIB="$STUB" nxgenesis
cp -f nxgenesis nxgenesis_nocl
cp -f nxgenesis "$HERE/nxgenesis_nocl_ocl.bak"

echo "== [2/2] OpenCL build =="
make clean >/dev/null 2>&1
make USE_OPENCL=1 EXTRALIBS="$EXTRALIBS" LEXLIB="$STUB" nxgenesis
# A copy under its own name, which the CUDA build (10_build.sh, whose make
# clean removes only nxgenesis) leaves alone, so the campaign can run CUDA and
# OpenCL arms from one checkout.
cp -f nxgenesis nxgenesis_ocl
[ -x nxgenesis_nocl ] || cp -f "$HERE/nxgenesis_nocl_ocl.bak" nxgenesis_nocl

# genesis/startup holds the scripts every GENESIS run loads through SIMPATH,
# schedule.g among them. `make install` puts them there; this script does not
# run it, and the directory is not tracked, so a fresh clone has none and any
# model that calls `schedule` -- VAnet2 -- stops at once without an error exit
# (found 2026-09-30, when the accelerator regression's VAnet2 arm came out
# empty in a clean clone). Copy them the way the install rule does.
( cd startup && mkdir -p ../../startup \
  && cp -f $(sed -n 's/^OBJS = //p' Makefile) ../../startup/ ) \
  || { echo "could not populate genesis/startup" >&2; exit 1; }
echo "== done =="
ls -la nxgenesis nxgenesis_nocl
ldd ./nxgenesis | grep -i opencl || echo "WARN: libOpenCL not linked"
