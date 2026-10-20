#!/bin/sh
# The paper's Code Ocean capsule: the CPU-only reproduction, the same that
# reproduce/run_all.sh --cpu-only runs on any Linux machine and the Dockerfile
# runs in a container. It builds GENESIS from source, measures model
# construction up to 1.7 million compartments, the CPU solver's modes, the
# action potential check and Table 3's gain from one solver per layer, and
# prints each number beside its published value with a verdict: about 13
# minutes on our laptop.
#
# Code Ocean runs it headless from /code and keeps only /results: the verdict
# table is in the run's output, the raw CSVs and logs in /results/reproduce.
# The capsule's environment installs, with apt-get: build-essential flex bison
# libncurses-dev python3. REPRO=quick runs the quick sizes instead.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${CODEOCEAN_RESULTS:-/results}
mkdir -p "$OUT"
QUICK=""
[ "${REPRO:-full}" = quick ] && QUICK=--quick
RESULTS="$OUT/reproduce"
export RESULTS
exec sh "$HERE/run_all.sh" --cpu-only $QUICK
