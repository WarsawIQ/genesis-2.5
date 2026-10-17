#!/bin/sh
# reproduce/measure.py must give back the published value of every number it
# can measure when it is handed our own campaign data as a reader's results,
# flag a number moved outside its tolerance, and refuse a run that measured
# nothing. Needs no GPU.
#
#     sh reproduce/tests/test_measure.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/measure_test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; [ -f "$T/out" ] && tail -15 "$T/out"; fail=1; }
M="python3 $ROOT/reproduce/measure.py"

# 1. Our own data, laid out as a reader's run, must give back every number.
if $M --self-test > "$T/out" 2>&1; then
    ok "our campaign data reproduce every number measure.py can measure"
else
    bad "self-test"
fi
grep -q "^self-test: [0-9][0-9]* numbers" "$T/out" || bad "self-test reports how many numbers it checked"

# 2. A construction exponent one higher must be flagged.
$M --stage-ours "$T/moved" > /dev/null 2>&1
for f in "$T/moved"/campaign/E3c_*_tidy.csv; do
    python3 - "$f" <<'EOF'
import csv, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
head = [l for l in lines if l.startswith("#")]
rows = list(csv.DictReader(l for l in lines if l and not l.startswith("#")))
for r in rows:
    if r["family"] == "con":
        r["wall_s"] = "%.6f" % (float(r["wall_s"]) * float(r["n"]) / 1000.0)
with open(p, "w", newline="") as f:
    f.write("\n".join(head) + ("\n" if head else ""))
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\n")
    w.writeheader(); w.writerows(rows)
EOF
done
$M "$T/moved" > "$T/out" 2>&1
grep "e3c_construction_exponent" "$T/out" | grep -q "OUTSIDE" \
    && ok "an exponent moved by one is OUTSIDE" || bad "moved exponent not flagged"

# 3. Nothing measured: exit 1.
mkdir -p "$T/empty"
if $M "$T/empty" > "$T/out" 2>&1; then bad "empty run accepted"; else
    grep -q "nothing measured" "$T/out" && ok "an empty run is refused" || bad "empty run message"
fi

# 4. Shape: a ratio within its own tolerance of 1 has no side; beyond it, the side counts.
if python3 - "$ROOT/reproduce" <<'EOF2'
import sys; sys.path.insert(0, sys.argv[1]); import measure
c = {"tolerance_pct": "10"}
got = [measure.shape(c, [1.08], 1.00), measure.shape(c, [4.2], 2.0), measure.shape(c, [1.08], 0.85)]
sys.exit(0 if got == ["info", "same shape", "DIFFERENT SHAPE"] else 1)
EOF2
then ok "shape: within the tolerance of 1 is information, beyond it the side counts"
else bad "shape verdicts"; fi

exit $fail
