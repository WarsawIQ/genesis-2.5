#!/bin/sh
# Refuse to time an Arbor other than the one the paper measured.
#
# On the UMCS login node the system python3.12 imports a pip Arbor 0.12.2 with
# no GPU support, while every Arbor arm in the paper ran the v0.10.0 CUDA build
# from cluster_bringup/toolchains/40_arbor_gpu.sh. A harness that forgets
# PYTHONPATH still runs -- and silently measures a different simulator on a
# different device. Every Arbor harness calls this first.
#
#     sh cluster_bringup/coreneuron/arbor_check.sh || exit 1
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/env.sh"

PYTHONPATH="$ARBOR_PY" \
LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
"$ARBOR_PYTHON" -c '
import sys
try:
    import arbor
except ImportError as e:
    sys.exit("arbor_check: cannot import Arbor from ARBOR_PY: %s" % e)
v, g = arbor.__version__, arbor.config()["gpu"]
if (v, g) != ("0.10.0", "cuda"):
    sys.exit("arbor_check: found Arbor %s (gpu=%s) at %s; the paper used 0.10.0 with CUDA. "
             "Run cluster_bringup/toolchains/40_arbor_gpu.sh or set ARBOR_PY." % (v, g, arbor.__file__))
print("arbor_check: Arbor %s with CUDA, %s" % (v, arbor.__file__))
'
