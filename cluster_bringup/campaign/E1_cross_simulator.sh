#!/bin/sh
# E1: the spiking-network comparison (paper Table 5), every arm in one session
# on inf03, replicates interleaved, so no ratio in the table mixes sessions
# (reviewer point 9). Adds a GENESIS fp64 GPU arm (point 4).
#
# The Vogels-Abbott COBAHH network, 4000 cells, 5 s simulated, dt 0.05 ms:
#   g_cpu_pub    GENESIS, CPU, the model as published (one solver per cell)
#   g_cpu_1s     GENESIS, CPU, one solver per layer
#   g_gpu32_1s   GENESIS, CUDA fp32, one solver per layer
#   g_gpu64_1s   GENESIS, CUDA fp64, one solver per layer
#   nrn_cpu      NEURON 9.0.2, compiled NMODL channels
#   nrn_cb_cpu   NEURON 9.0.2, the original ChannelBuilder channels
#   cn_cpu       CoreNEURON, CPU
#   cn_gpu       CoreNEURON, GPU (standalone special-core, NVHPC 24.11)
#   arbor_gpu    Arbor 0.10.0, GPU
#
# Needs the toolchains (10, 20, 30, 40, 45 and fetch_modeldb_83319.sh), the
# COBAHH model prepared (coreneuron/prepare_cobahh.sh, build_mechanisms.sh cpu
# and gpu) and both GENESIS binaries (10_build.sh). ~65 min.
set -u
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
REPS=${REPS:-5}
[ "$CAMPAIGN_DRY" = 1 ] && REPS=${REPS_DRY:-1}

campaign_init E1
cuda_env
W="$RUN_DIR/campaign_E1"
mkdir -p "$W"

# --- preconditions: refuse rather than measure a partial table
need() { [ -e "$1" ] || { echo "REFUSED: missing $1 ($2)" >&2; exit 2; }; }
need genesis/src/nxgenesis "cluster_bringup/10_build.sh"
need genesis/src/nxgenesis_nocl "cluster_bringup/10_build.sh"
need "$COBAHH_DIR/x86_64" "coreneuron/build_mechanisms.sh cpu"
need "$COBAHH_GPU_MECH/x86_64/special-core" "coreneuron/build_mechanisms.sh gpu"
need "$ARBOR_COBAHH_CAT" "toolchains/45_arbor_cobahh_catalogue.sh"
sh cluster_bringup/coreneuron/arbor_check.sh > "$W/arbor_check.log" 2>&1 \
    || { echo "REFUSED: Arbor does not load, see $W/arbor_check.log" >&2; exit 2; }
env PYTHONPATH="$ARBOR_PY" LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
    "$ARBOR_PYTHON" -c 'import arbor, sys; print(sorted(arbor.load_catalogue(sys.argv[1]).keys()))' \
    "$ARBOR_COBAHH_CAT" >> "$W/arbor_check.log" 2>&1 \
    || { echo "REFUSED: $ARBOR_COBAHH_CAT does not load here, see $W/arbor_check.log" >&2; exit 2; }

for a in g_cpu_pub g_cpu_1s g_gpu32_1s g_gpu64_1s; do vanet2_workdir "$W/$a"; done
# NEURON with the ChannelBuilder channels: a copy of the model without the
# compiled mechanisms, so NEURON falls back to the originals. The model loads
# ../common/init.hoc, so the copy must keep cobahh and common side by side
# (copying cobahh alone left create_net undefined; found by the dry run).
rm -rf "$W/cb"; mkdir -p "$W/cb"
cp -a "$COBAHH_DIR" "$W/cb/cobahh"
cp -a "$(dirname "$COBAHH_DIR")/common" "$W/cb/common"
rm -rf "$W/cb/cobahh"/x86_64*
# CoreNEURON GPU runs a model dumped once by NEURON.
DUMP="$RUN_DIR/cobahh_coredat"
if [ ! -f "$DUMP/files.dat" ]; then
    REPS=0 sh cluster_bringup/coreneuron/coreneuron_gpu_standalone.sh > "$W/cn_dump.log" 2>&1
    need "$DUMP/files.dat" "the NEURON dump for CoreNEURON GPU, see $W/cn_dump.log"
fi
CN_LIBS="$NRN_GPU_BUILD/lib:$NVHPC_ROOT/compilers/lib:$NVHPC_ROOT/cuda/12.6/lib64"

# spike counts printed or written by the other simulators
out_dat_spikes() { wc -l < "$SPIKE_DIR/out.dat"; }
arbor_spikes()   { sed -n 's/^RESULT_SPIKES=//p' "$1"; }
cn_gpu_spikes()  { grep -E "Number of spikes:" "$1" | grep -oE '[0-9]+' | tail -1; }

arm() {   # <arm> <rep> <order>
    unset EXPECT_NCOMP EXPECT_SPIKES SPIKES_OF SANITY_RE
    case "$1" in
    g_cpu_pub)
        run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_vanet2 \
            sh -c "cd '$W/$1' && exec timeout 3600 '$GENESIS_ROOT/genesis/src/nxgenesis_nocl' -notty -batch VAnet2-batch.g" ;;
    g_cpu_1s)
        EXPECT_NCOMP=4000
        run_rep "$1" "$2" "$3" 0 "$BANNER_CPU" sanity_vanet2 \
            sh -c "cd '$W/$1' && exec timeout 3600 '$GENESIS_ROOT/genesis/src/nxgenesis_nocl' -notty -batch VAnet2-batch-1solver.g" ;;
    g_gpu32_1s)
        EXPECT_NCOMP=4000
        run_rep "$1" "$2" "$3" 1 "$BANNER_CUDA32" sanity_vanet2 \
            sh -c "cd '$W/$1' && exec timeout 3600 '$GENESIS_ROOT/genesis/src/nxgenesis' -notty -batch VAnet2-batch-1solver.g" ;;
    g_gpu64_1s)
        EXPECT_NCOMP=4000
        run_rep "$1" "$2" "$3" 1 "$BANNER_CUDA64" sanity_vanet2 \
            sh -c "cd '$W/$1' && exec env GENESIS_GPU_PRECISION=fp64 timeout 3600 '$GENESIS_ROOT/genesis/src/nxgenesis' -notty -batch VAnet2-batch-1solver.g" ;;
    nrn_cpu)
        EXPECT_SPIKES=558824 SPIKES_OF=out_dat_spikes SPIKE_DIR=$COBAHH_DIR
        run_rep "$1" "$2" "$3" 0 "$BANNER_ANY" sanity_spikes \
            sh -c "cd '$COBAHH_DIR' && rm -f out.dat && PATH='$NRN_PIP_BIN':\$PATH exec timeout 3600 '$NRN_PYTHON' run_plain.py" ;;
    nrn_cb_cpu)
        EXPECT_SPIKES=574138 SPIKES_OF=out_dat_spikes SPIKE_DIR=$W/cb/cobahh
        run_rep "$1" "$2" "$3" 0 "$BANNER_ANY" sanity_spikes \
            sh -c "cd '$W/cb/cobahh' && rm -f out.dat && PATH='$NRN_PIP_BIN':\$PATH exec timeout 3600 '$NRN_PYTHON' run_plain.py" ;;
    cn_cpu)
        EXPECT_SPIKES=558824 SPIKES_OF=out_dat_spikes SPIKE_DIR=$COBAHH_DIR
        run_rep "$1" "$2" "$3" 0 "$BANNER_ANY" sanity_spikes \
            sh -c "cd '$COBAHH_DIR' && rm -f out.dat && PATH='$NRN_PIP_BIN':\$PATH exec timeout 3600 '$NRN_PYTHON' run_core.py" ;;
    cn_gpu)
        SANITY_RE='Solver Time' SANITY_METRIC=solver_s
        mkdir -p "$W/cn_gpu"
        run_rep "$1" "$2" "$3" 1 "$BANNER_ANY" sanity_grep \
            sh -c "cd '$W/cn_gpu' && exec env LD_LIBRARY_PATH='$CN_LIBS':\${LD_LIBRARY_PATH:-} timeout 1800 \
                '$COBAHH_GPU_MECH/x86_64/special-core' --datpath '$DUMP' --gpu --tstop 5000 --dt 0.05" ;;
    arbor_gpu)
        EXPECT_SPIKES=602720 SPIKES_OF=arbor_spikes
        mkdir -p "$W/arbor_gpu"
        run_rep "$1" "$2" "$3" 1 "$BANNER_ANY" sanity_spikes \
            env -C "$W/arbor_gpu" USE_GPU=1 ARBOR_COBAHH_CAT="$ARBOR_COBAHH_CAT" PYTHONPATH="$ARBOR_PY" \
            LD_LIBRARY_PATH="$CUDA_HOME/lib64:$ARBOR_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
            timeout 3600 "$ARBOR_PYTHON" "$GENESIS_ROOT/cluster_bringup/arbor_vanet2/vanet2_arbor.py" ;;
    esac
}
export SANITY_METRIC=value

run_arms "$REPS" arm g_cpu_pub g_cpu_1s g_gpu32_1s g_gpu64_1s nrn_cpu nrn_cb_cpu cn_cpu cn_gpu arbor_gpu
st=$?
campaign_done "$st" \
    "1solver_speedup_cpu=g_cpu_pub/g_cpu_1s" \
    "vs_coreneuron_cpu=cn_cpu/g_cpu_1s" "vs_neuron_cpu=nrn_cpu/g_cpu_1s" \
    "published_vs_coreneuron_cpu=cn_cpu/g_cpu_pub" "published_vs_neuron_cpu=nrn_cpu/g_cpu_pub" \
    "coreneuron_over_neuron=nrn_cpu/cn_cpu" "channelbuilder_over_nmodl=nrn_cb_cpu/nrn_cpu" \
    "gpu32_over_cpu=g_gpu32_1s/g_cpu_1s" "gpu64_over_gpu32=g_gpu64_1s/g_gpu32_1s" \
    "coreneuron_gpu_ahead=g_gpu32_1s/cn_gpu" "arbor_over_genesis_gpu=arbor_gpu/g_gpu32_1s"
exit $st
