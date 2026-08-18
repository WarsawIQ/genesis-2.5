#!/bin/bash
# Does firing rate change the cost of this benchmark?
#
# The Vm cross-check shows the three implementations settle at different firing
# rates on the multi-compartment model -- GENESIS around 70 Hz, NEURON and Arbor
# around 10 Hz -- because GENESIS writes its Hodgkin-Huxley rates about
# EREST = -70 mV while NEURON's hh.mod is written about -65 mV, a 5 mV offset in
# the rate constants.
#
# That invites the objection that Table 7 does not compare the same computation.
# It does, and this measures it rather than arguing it: the model has no
# synapses and no events, so a spike costs nothing beyond the channel update
# every compartment performs every step regardless. Each simulator is run twice,
# once driven and once with the injection off, and the wall times compared.
#
# If the two arms of a simulator agree, firing rate is not in the measurement.
set -u
N=${N:-10000}
K=${K:-5000}
REPS=${REPS:-3}
OUT="$HOME/genesis-2.5/cluster_bringup/logs/rate_vs_walltime_$(hostname)_$(date +%Y%m%d_%H%M%S).csv"

GEN_LD="/storage/opt/cuda/cuda-12.8/lib64"
ARB_P="$HOME/opt/arbor-gpu/lib/python3.13/site-packages"
PY="$HOME/opt/miniforge/bin/python3"
export GENESIS_OCL_TREE_MAX_NCOMPTS=0

USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
[ "${ALLOW_BUSY_GPU:-0}" = 1 ] || [ "$USED" -le 500 ] || {
    echo "ABORT: $USED MiB already on the card" >&2; exit 1; }

echo "simulator,backend,driven,rep,wall_s" > "$OUT"
echo "== firing rate vs wall time, N=$N K=$K on $(hostname) =="

for driven in 1 0; do
    # ---- GENESIS GPU ----
    cd "$HOME/genesis-2.5" || exit 1
    for r in $(seq 1 "$REPS"); do
        NOINJ=0; [ "$driven" = 0 ] && NOINJ=1
        S=$(date +%s%N)
        LD_LIBRARY_PATH="$GEN_LD" env GENESIS_BENCH_CHANMODE=4 GENESIS_BENCH_NCOMP=16 \
            GENESIS_BENCH_NOINJECT=$NOINJ GENESIS_CUDA_MULTILOOP=$((K + 10)) \
            timeout 3600 ./genesis/src/nxgenesis -nosimrc -notty -batch \
            genesis/Scripts/benchmark/hh_multicompartment_createmap.g "$N" "$K" >/dev/null 2>&1
        E=$(date +%s%N)
        echo "GENESIS 2.5,GPU,$driven,$r,$(awk "BEGIN{printf \"%.4f\", ($E-$S)/1e9}")" >> "$OUT"
    done

    # ---- Arbor GPU ----
    cd "$HOME" || exit 1
    AMP=0.5; [ "$driven" = 0 ] && AMP=0.0
    for r in $(seq 1 "$REPS"); do
        w=$(PYTHONPATH="$ARB_P" LD_LIBRARY_PATH="$GEN_LD:$HOME/opt/arbor-gpu/lib" \
            USE_GPU=1 INJECT_NA=$AMP timeout 3600 "$PY" hh_multicomp_arbor.py "$N" "$K" 2>&1 \
            | sed -n 's/^RESULT_WALL_S=//p')
        echo "Arbor 0.10.0,GPU,$driven,$r,${w:-NA}" >> "$OUT"
    done

    # ---- NEURON CPU ----
    cd "$HOME/nrn_multicomp" 2>/dev/null || { echo "no nrn_multicomp"; exit 1; }
    for r in $(seq 1 "$REPS"); do
        w=$(INJECT_NA=$AMP USE_CORENEURON=0 timeout 3600 python3.12 \
            hh_multicomp_neuron.py "$N" "$K" 2>&1 | sed -n 's/^RESULT_WALL_S=//p')
        echo "NEURON 9.0.2,CPU,$driven,$r,${w:-NA}" >> "$OUT"
    done
    echo "  driven=$driven done $(date +%T)"
done

echo "== $OUT =="
awk -F, 'NR>1 && $5!="NA" {k=$1" "$2" driven="$3; s[k]+=$5; n[k]++}
         END{for (i in s) printf "  %-28s %7.3f s (n=%d)\n", i, s[i]/n[i], n[i]}' "$OUT" | sort
