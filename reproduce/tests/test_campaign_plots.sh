#!/bin/sh
# The campaign figures must be drawable the morning after the first night, so
# plot_campaign_figures.py is tested here against SYNTHETIC session files in
# the campaign CSV format (fixtures/make_campaign_fixture.py: obviously fake
# values that live only under a test's temp dir).
# Skips, not fails, where matplotlib is missing (as in the CPU-only CI job).
#
#     sh reproduce/tests/test_campaign_plots.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 -c "import matplotlib" 2>/dev/null || { echo "skip  campaign plots (no matplotlib)"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/campaign_plots.XXXXXX")
trap 'rm -rf "$T"' EXIT

python3 "$ROOT/reproduce/tests/fixtures/make_campaign_fixture.py" "$T/campaign" > /dev/null

CAMP="$T/campaign"
cd "$ROOT" || exit 1
if python3 paper/scripts/plot_campaign_figures.py --campaign "$CAMP" --out "$T/figs" > "$T/out" 2>&1; then
    n=$(ls "$T/figs"/fig_*.pdf 2>/dev/null | wc -l)
    if [ "$n" = 4 ]; then echo "ok    campaign plots: 4 figures from synthetic sessions"
    else echo "FAIL  campaign plots: $n of 4 figures"; cat "$T/out"; exit 1; fi
else echo "FAIL  campaign plots"; cat "$T/out"; exit 1; fi

# Half-finished campaign: a missing experiment must refuse, naming it
rm "$CAMP"/E4_*.csv
if python3 paper/scripts/plot_campaign_figures.py --campaign "$CAMP" --out "$T/figs2" > "$T/out" 2>&1; then
    echo "FAIL  a campaign without E4 was accepted"; exit 1
elif grep -q "no data yet for: E4" "$T/out"; then
    echo "ok    a missing experiment refuses and names itself"
else echo "FAIL  wrong refusal"; cat "$T/out"; exit 1; fi
echo "all campaign plot checks passed"
