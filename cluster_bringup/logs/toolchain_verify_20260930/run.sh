#!/bin/bash
export WORK_DIR=$HOME/tc-verify-20260929
cd $HOME/f0-verify/genesis-2.5
echo "START $(date -Is) commit $(git rev-parse --short HEAD) WORK_DIR=$WORK_DIR"
for s in "bash cluster_bringup/toolchains/30_neuron_gpu.sh" "bash cluster_bringup/coreneuron/build_mechanisms.sh gpu"; do
  echo "=== $s  $(date -Is)"
  t0=$(date +%s)
  if $s; then echo "=== OK $(( $(date +%s) - t0 )) s"; else echo "=== FAILED rc=$? after $(( $(date +%s) - t0 )) s"; echo "END FAILED $(date -Is)"; exit 1; fi
done
echo "END OK $(date -Is)"; du -sh $WORK_DIR
