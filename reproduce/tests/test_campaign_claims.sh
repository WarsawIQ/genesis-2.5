#!/bin/sh
# The staged campaign claims must work the morning they are needed: this stages
# them against SYNTHETIC campaign sessions (fixtures/make_campaign_fixture.py,
# known expected values) in a throw-away copy of the repository and checks the
# values make_numbers.py computes, the handling of missing experiments, and
# idempotence. Needs no GPU and no campaign.
#
#     sh reproduce/tests/test_campaign_claims.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/campaign_claims.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@"; fail=1; }

mkdir -p "$T/r"
(cd "$ROOT" && git ls-files -co --exclude-standard | tar cf - -T -) | (cd "$T/r" && tar xf -)
CAMP="$T/r/cluster_bringup/logs/campaign_v2.6.0-rc1"
python3 "$ROOT/reproduce/tests/fixtures/make_campaign_fixture.py" "$CAMP" > /dev/null

# 1. an experiment whose night has not happened yet is waited for, not faked
mkdir -p "$T/hold"; mv "$CAMP"/E7_*.csv "$T/hold/"
out=$(cd "$T/r" && sh reproduce/stage_campaign_claims.sh)
if echo "$out" | grep -q "waiting for data: E7_INF03" && echo "$out" | grep -q "^added 2[0-9] claim rows"; then
    ok "staging without E7: the rest lands, E7 is reported as waiting"
else bad "partial staging" "$out"; fi
(cd "$T/r" && python3 reproduce/make_numbers.py > "$T/out" 2>&1) \
    && ok "make_numbers accepts the staged rows" || bad "make_numbers" "$(cat "$T/out")"

# 2. the missing experiment arrives; only its rows are added
mv "$T/hold"/* "$CAMP"/
out=$(cd "$T/r" && sh reproduce/stage_campaign_claims.sh)
if echo "$out" | grep -q "^added 3 claim rows, 2[0-9] already present$"; then
    ok "the late experiment adds exactly its own rows"
else bad "late staging" "$out"; fi
(cd "$T/r" && python3 reproduce/make_numbers.py > /dev/null 2>&1) || bad "make_numbers after E7"

# 3. the values are what the fixture was built to give
check() {   # id, expected, relative tolerance %
    got=$(grep "^$1," "$T/r/reproduce/published.csv" | cut -d, -f2)
    [ -n "$got" ] || { bad "$1 missing from published.csv"; return; }
    if python3 -c "import sys; sys.exit(0 if abs($got - $2) <= abs($2) * $3 / 100.0 else 1)"; then
        ok "$1 = $got (expected about $2)"
    else bad "$1 = $got, expected $2 within $3%"; fi
}
check e2_max_e2e_a40 62.5 10
check e2_max_e2e_a100 83.3 10
check e2_fp64_cost_a40 1.30 6
check e4_crossover_k_a40 1000 20
check e4_crossover_k_fp64_a40 4000 20
check e7_inter_over_uniform 1.30 6
check e7_cpu_inter_over_uniform 1.00 6
check e8_gain_tree_k5000_a100 5.0 60
check e3c_construction_exponent 1.00 4
check e3c_construction_1700k_s 10.0 6

# 4. running it again changes nothing
out=$(cd "$T/r" && sh reproduce/stage_campaign_claims.sh)
case "$out" in "added 0 claim rows, "*) ok "idempotent" ;; *) bad "second run" "$out" ;; esac

# 5. two sessions of one experiment refuse (never silently pick one)
cp "$CAMP"/E2_inf02_20990101_000000.csv "$CAMP"/E2_inf02_20990102_000000.csv
if out=$(cd "$T/r" && sh reproduce/stage_campaign_claims.sh 2>&1); then
    bad "two E2 sessions were accepted" "$out"
elif echo "$out" | grep -q "REFUSED: 2 session files"; then
    ok "two sessions of one experiment refuse"
else bad "two sessions: wrong message" "$out"; fi

[ "$fail" = 0 ] && echo "all staged-claim checks passed"
exit "$fail"
