# Where everything lives. Sourced by every cluster, toolchain and reproduction
# script:
#
#     . "$ROOT/cluster_bringup/env.sh"
#
# Each location is defined once, here, as VAR=${VAR:-default}, so any of them
# can be overridden from the environment. The defaults are the ones used on the
# UMCS "Lunar" cluster (login node miranda, GPU nodes inf02 = A40 and
# inf03 = A100), where every result in the paper was measured.
#
# Before this file existed the same paths were written out in some thirty
# scripts, and several results could only be reproduced from files in one
# user's home directory. reproduce/check_paths.sh now fails on any path written
# out anywhere else.
#
# Assignments and exports only: sourcing this file must never have side effects.

# The checkout this file belongs to. Callers normally set ROOT first.
GENESIS_ROOT=${GENESIS_ROOT:-${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}}

# Root for installed tools (cluster_bringup/toolchains/) and scratch runs. Point
# it at an empty directory to rebuild everything from scratch.
WORK_DIR=${WORK_DIR:-$HOME}
RUN_DIR=${RUN_DIR:-$WORK_DIR/runs}
SCRATCH=${SCRATCH:-${TMPDIR:-/tmp}}

# CUDA. The GENESIS CUDA backend is built and measured with 12.8; the OpenCL
# build takes its CL headers from the 13.0 toolkit on this cluster. Off the
# cluster the usual /usr/local/cuda is taken if it exists.
if [ -z "${CUDA_HOME:-}" ]; then
    for _d in /storage/opt/cuda/cuda-12.8 /usr/local/cuda; do
        [ -d "$_d" ] && { CUDA_HOME=$_d; break; }
    done
    unset _d
fi
CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
OPENCL_CUDA_HOME=${OPENCL_CUDA_HOME:-/storage/opt/cuda/cuda-13.0}

# Build tools for NEURON and Arbor. Every such build used the system CMake
# 3.26: the pip-installed CMake 4 that comes first on PATH on miranda cannot
# build Arbor 0.10 (CMake 4 removed find_package(CUDA)). The host-side NEURON
# tools and Arbor were compiled with gcc-toolset-13; the system GCC 8.5 needs
# -lstdc++fs for std::filesystem and fails to link them.
CMAKE=${CMAKE:-/usr/bin/cmake}
GCC_TOOLSET=${GCC_TOOLSET:-/opt/rh/gcc-toolset-13/root/usr}

# Python 3.13 with development headers, for Arbor and the NEURON GPU build.
MINIFORGE=${MINIFORGE:-$WORK_DIR/opt/miniforge}
ARBOR_PYTHON=${ARBOR_PYTHON:-$MINIFORGE/bin/python3}

# NEURON 9.0.2 from pip, for every CPU arm. The system python3.12 on miranda
# also has an Arbor 0.12.2 without GPU support installed; Arbor arms must use
# ARBOR_PYTHON with ARBOR_PY, never this one.
NRN_PYTHON=${NRN_PYTHON:-python3.12}
NRN_PIP_BIN=${NRN_PIP_BIN:-$HOME/.local/bin}

# CoreNEURON on the GPU: NVHPC 24.11, and NEURON 9.0.2 built with it.
NVHPC_ROOT=${NVHPC_ROOT:-$WORK_DIR/opt/nvhpc24/Linux_x86_64/24.11}
NRN_GPU_SRC=${NRN_GPU_SRC:-$WORK_DIR/nrn_src}
NRN_GPU_BUILD=${NRN_GPU_BUILD:-$NRN_GPU_SRC/build-gpu}

# Arbor v0.10.0 built with CUDA, for the Ice Lake CPUs of the GPU nodes (the
# paper's build was -march=native on one of them).
ARBOR_PREFIX=${ARBOR_PREFIX:-$WORK_DIR/opt/arbor-gpu}
ARB_ARCH=${ARB_ARCH:-icelake-server}
ARBOR_PY=${ARBOR_PY:-$ARBOR_PREFIX/lib/python3.13/site-packages}

# ModelDB 83319 (Brette et al. 2007), unpacked, and the Vogels-Abbott COBAHH
# model inside it. The GPU mechanisms are built into COBAHH_GPU_MECH with
# -lstdc++fs; the directory without it does not load (see
# cluster_bringup/coreneuron/README.md).
MODELDB_DIR=${MODELDB_DIR:-$WORK_DIR/coreneuron_cmp}
COBAHH_DIR=${COBAHH_DIR:-$MODELDB_DIR/destexhe_benchmarks/NEURON/cobahh}
COBAHH_GPU_MECH=${COBAHH_GPU_MECH:-$COBAHH_DIR/x86_64_gpu2}

# MPI launcher for the PGENESIS scaling runs.
MPIRUN=${MPIRUN:-mpirun}

export GENESIS_ROOT WORK_DIR RUN_DIR SCRATCH CUDA_HOME OPENCL_CUDA_HOME
export CMAKE GCC_TOOLSET MINIFORGE ARBOR_PYTHON NRN_PYTHON NRN_PIP_BIN NVHPC_ROOT NRN_GPU_SRC
export NRN_GPU_BUILD ARBOR_PREFIX ARB_ARCH ARBOR_PY MODELDB_DIR COBAHH_DIR
export COBAHH_GPU_MECH MPIRUN
