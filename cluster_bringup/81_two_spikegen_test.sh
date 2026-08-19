#!/bin/sh
# One hsolve, two spike generators.
#
# GENESIS refuses this at SETUP, which is the constraint that forces a spiking
# network into one solver per cell and leaves the accelerator paying a dispatch
# per cell per step. This script is the pass condition for lifting that
# refusal: it exits 0 only when SETUP accepts the model and ten steps run.
#
# It distinguishes the three ways this can go wrong -- still refused, SETUP
# broken some other way, SETUP fine but stepping broken -- because "it failed"
# is not enough to act on.
#
# Prepared by Karol Chlasta (karol@chlasta.pl).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT" || exit 1
BIN=${BIN:-./genesis/src/nxgenesis_nocl}
OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT

"$BIN" -nosimrc -notty -batch \
    genesis/Scripts/benchmark/two_spikegen_setup.g > "$OUT" 2>&1

if grep -q "second spikegen" "$OUT"; then
    echo "FAIL: SETUP still refuses a second spikegen"
    grep "second spikegen" "$OUT" | head -1
    exit 1
fi
if ! grep -q "^SETUP_OK" "$OUT"; then
    echo "FAIL: SETUP did not complete"; tail -5 "$OUT"; exit 1
fi
if ! grep -q "^STEP_OK" "$OUT"; then
    echo "FAIL: SETUP completed but stepping did not"; tail -5 "$OUT"; exit 1
fi
echo "PASS: $(grep '^SETUP_OK' "$OUT")"
exit 0
