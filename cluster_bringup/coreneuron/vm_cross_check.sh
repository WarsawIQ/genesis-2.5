#!/bin/bash
# Do the three implementations of the multi-compartment benchmark actually
# integrate the same model?
#
# Table 7 compares GENESIS, NEURON and Arbor on throughput and argues
# equivalence from matching geometry, conductances, injection and timestep.
# That is an argument, not a measurement, and it is the weakest point in the
# comparison. This measures it: one cell, 500 ms, Vm recorded at the soma and
# at the centre of the last dendrite in all three, plus the firing rate.
#
# Two invariants are compared, chosen because the model fires repetitively
# under constant current:
#   * the first action potential -- shape and peak time, before phase drift
#     accumulates;
#   * the firing rate over 500 ms -- what survives phase drift.
# Comparing Vm at t=500 ms would be a test an honest implementation fails, for
# the same reason the fp32/fp64 comparison in the paper uses a single-AP window.
#
# The far-end probe is the one that exercises axial coupling, which is the part
# hines_tree_eliminate moves onto the GPU.
set -u
R="$HOME/genesis-2.5"
OUT="${OUT:-$HOME/vmcross}"
K=${K:-50000}
N=1
mkdir -p "$OUT"
cd "$HOME" || exit 1

export LD_LIBRARY_PATH="/storage/opt/cuda/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}"
ARB_PY="$HOME/opt/miniforge/bin/python3"
ARB_PP="$HOME/opt/arbor-gpu/lib/python3.13/site-packages"

echo "== Vm cross-check: N=$N, K=$K steps (dt=0.01 ms => $(awk "BEGIN{print $K*0.01}") ms) on $(hostname) =="
nvidia-smi --query-gpu=name --format=csv,noheader | head -1

# ---------------------------------------------------------------- GENESIS ----
# The trace script is hh_multicompartment_createmap.g verbatim down to `reset`,
# with a per-step readout in place of the timing tail.
run_genesis() {
    label=$1; mode=$2
    echo "-- GENESIS $label (chanmode=$mode) --"
    ( cd "$R" && GENESIS_BENCH_NCOMP=16 GENESIS_BENCH_CHANMODE=$mode \
        ./genesis/src/nxgenesis -nosimrc -notty -batch \
        genesis/Scripts/benchmark/hh_multicomp_vmtrace.g $N $K 2>&1 ) \
        | sed -n 's/^TRACE //p' | awk 'NF==4{print $2","$3","$4}' \
        > "$OUT/genesis_${label}_raw.csv"
    n=$(wc -l < "$OUT/genesis_${label}_raw.csv")
    if [ "$n" -lt 2 ]; then echo "   FAILED: $n rows"; return 1; fi
    { echo "t_ms,vm_soma_mV,vm_far_mV"; cat "$OUT/genesis_${label}_raw.csv"; } \
        > "$OUT/genesis_${label}.csv"
    rm -f "$OUT/genesis_${label}_raw.csv"
    echo "   $n samples -> genesis_${label}.csv"
}

run_genesis cpu 1
run_genesis gpu 4

# ----------------------------------------------------------------- NEURON ----
echo "-- NEURON --"
cd "$HOME/nrn_multicomp" 2>/dev/null || { echo "   no nrn_multicomp dir"; exit 1; }
cp -f "$HOME/hh_multicomp_neuron.py" .
out=$(TRACE=1 TRACE_CSV="$OUT/neuron.csv" USE_CORENEURON=0 \
      timeout 3600 python3.12 hh_multicomp_neuron.py $N $K 2>&1)
echo "$out" | sed -n 's/^RESULT_\(TRACE_SAMPLES\|SPIKES_CELL0\|RATE_HZ\|VM_SOMA\|VM_FAR\)=/   \1=/p'
echo "$out" | grep -q RESULT_TRACE_CSV || { echo "   FAILED"; echo "$out" | tail -5; }

# ------------------------------------------------------------------ ARBOR ----
cd "$HOME" || exit 1
for arm in cpu gpu; do
    g=0; [ "$arm" = gpu ] && g=1
    echo "-- Arbor $arm --"
    out=$(PYTHONPATH="$ARB_PP" LD_LIBRARY_PATH="/storage/opt/cuda/cuda-12.8/lib64:$HOME/opt/arbor-gpu/lib:$LD_LIBRARY_PATH" \
          TRACE=1 TRACE_CSV="$OUT/arbor_$arm.csv" USE_GPU=$g \
          timeout 3600 "$ARB_PY" hh_multicomp_arbor.py $N $K 2>&1)
    echo "$out" | sed -n 's/^RESULT_\(TRACE_SAMPLES\|SPIKES_CELL0\|RATE_HZ\|VM_SOMA\|VM_FAR\|CTX\)=/   \1=/p'
    echo "$out" | grep -q RESULT_TRACE_CSV || { echo "   FAILED"; echo "$out" | tail -6; }
done

echo
echo "== traces in $OUT =="
ls -la "$OUT"/*.csv 2>/dev/null | awk '{print "  "$5" bytes  "$9}'
