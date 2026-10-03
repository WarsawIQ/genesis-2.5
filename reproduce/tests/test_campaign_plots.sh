#!/bin/sh
# The campaign figures must be drawable the morning after the first night, so
# plot_campaign_figures.py is tested here against SYNTHETIC session files in
# the campaign CSV format (obviously fake values; the generator is below, and
# the claim map could never read them: they live under a test's temp dir).
# Skips, not fails, where matplotlib is missing (as in the CPU-only CI job).
#
#     sh reproduce/tests/test_campaign_plots.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 -c "import matplotlib" 2>/dev/null || { echo "skip  campaign plots (no matplotlib)"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/campaign_plots.XXXXXX")
trap 'rm -rf "$T"' EXIT

python3 - "$T" <<'EOF'
import os, random, sys
d = os.path.join(sys.argv[1], "campaign"); os.makedirs(d)
random.seed(7)
HEAD = "# experiment: %s\n# session: %s\n# commit: 0000000000000000000000000000000000000000\n# node: %s\n# gpu: NVIDIA %s\n"
COLS = "session,experiment,arm,rep,order,wall_s,metric,metric_value,status,started\n"

def write(exp, node, gpu, arms):
    s = "%s_20990101_000000" % node
    with open(os.path.join(d, "%s_%s.csv" % (exp, s)), "w") as f:
        f.write(HEAD % (exp, s, node, gpu)); f.write(COLS)
        for arm, wall, metric in arms:
            f.write("%s,%s,%s,0,1,%.3f,t,%.5f,ok,t0\n" % (s, exp, arm, wall * 1.1, metric))
            for rep in (1, 2, 3):
                j = random.uniform(0.97, 1.03)
                f.write("%s,%s,%s,%d,1,%.3f,t,%.5f,ok,t0\n" % (s, exp, arm, rep, wall * j, metric * j))
            f.write("%s,%s,%s,4,1,0.001,,,rejected: synthetic,t0\n" % (s, exp, arm))

for node, gpu, f in (("inf02", "A40", 1.0), ("inf03", "A100", 0.6)):
    write("E2", node, gpu,
          [("cpu_k%d" % k, 0.02 * k, 0) for k in (200, 1000, 5000)]
          + [("g32_k%d" % k, 1.2 + 0.0002 * k * f, 0) for k in (200, 1000, 5000)]
          + [("g64_k%d" % k, 1.3 + 0.0004 * k * f, 0) for k in (200, 1000, 5000)])
    write("E3", node, gpu,
          [(p % n, w * n / 1000.0, m * n / 1000.0)
           for n in (1000, 10000, 50000)
           for p, w, m in (("t2_cpu_n%d", 6.0, 5.0), ("t2_cuda_n%d", 1.5 * f, 0.1 * f),
                           ("t2_ocl_n%d", 1.7 * f, 0.12 * f))])
    write("E4", node, gpu,
          [(p % k, a + b * k * f, 0) for k in (1000, 5000, 20000)
           for p, a, b in (("g32_k%d", 1.2, 0.0002), ("g64_k%d", 1.3, 0.0004),
                           ("arb_k%d", 0.9, 0.0005))])
write("E3c", "inf03", "none", [("con_n%d" % n, 0.0001 * n, 0) for n in (1000, 8000, 31000)])
print(d)
EOF

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
