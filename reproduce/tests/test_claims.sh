#!/bin/sh
# The claim map has to fail loudly when its inputs are wrong, or it is no
# better than typing the numbers. Each case below breaks one thing in a
# throw-away copy of the repository and checks that make_numbers.py refuses,
# naming the claim, and writes nothing.
#
#     sh reproduce/tests/test_claims.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/claims_test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0

fresh() {
    rm -rf "$T/r"; mkdir -p "$T/r"
    (cd "$ROOT" && git ls-files -co --exclude-standard | tar cf - -T -) | (cd "$T/r" && tar xf -)
}
run() { (cd "$T/r" && python3 reproduce/make_numbers.py "$@" > "$T/out" 2>&1); }
expect_fail() {    # $1 label, $2 text the error must contain
    if run; then echo "FAIL  $1: accepted"; fail=1
    elif ! grep -q "$2" "$T/out"; then echo "FAIL  $1: wrong message"; cat "$T/out"; fail=1
    else echo "ok    $1"; fi
}

fresh
if run && run --check; then echo "ok    clean map regenerates with no changes"
else echo "FAIL  clean map"; cat "$T/out"; fail=1; fi

fresh
mv "$T/r/cluster_bringup/logs/opencl_cluster_20260818.csv" "$T/r/gone.csv"
expect_fail "missing data file" "singlecomp_ocl_a40_n500: data file .* does not exist"

fresh
printf '| `cluster_bringup/logs/opencl_cluster_20260818.csv` | test | none |\n' \
    >> "$T/r/cluster_bringup/logs/SUPERSEDED.md"
expect_fail "superseded data file" "is marked superseded"

fresh
printf 'bad_cross_session,test,derived,x,%%.1f,ksweep_e2e_k5000 / singlecomp_cuda_a100_n50000,,,,,,,ksweep_e2e_k5000;singlecomp_cuda_a100_n50000,,,none,,,,\n' \
    >> "$T/r/reproduce/claims.csv"
expect_fail "ratio across sessions" "bad_cross_session: inputs come from different sessions"

fresh
printf 'bad_formula,test,derived,x,%%.1f,no_such_claim * 2,,,,,,,no_such_claim,,,none,,,,\n' \
    >> "$T/r/reproduce/claims.csv"
expect_fail "unknown input" "no_such_claim: unknown input"

fresh
mkdir -p "$T/r/cluster_bringup/logs/campaign_dry"
cp "$T/r/cluster_bringup/logs/opencl_cluster_20260818.csv" "$T/r/cluster_bringup/logs/campaign_dry/x.csv"
sed -i 's|cluster_bringup/logs/opencl_cluster_20260818.csv|cluster_bringup/logs/campaign_dry/x.csv|' "$T/r/reproduce/claims.csv"
expect_fail "data from a campaign dry run" "from a campaign dry run"

fresh
if (cd "$T/r" && python3 reproduce/make_numbers.py --strict > "$T/out" 2>&1); then
    echo "ok    --strict passes (no prose claims left)"
elif grep -q -- "--strict: no raw data" "$T/out"; then
    echo "ok    --strict refuses while prose claims remain"
else echo "FAIL  --strict"; cat "$T/out"; fail=1; fi

# The manuscript side: a mistyped \claim id must stop the LaTeX build, and a
# result typed by hand must be found by the lint. Needs pdflatex for the first;
# PDFLATEX can name another command (e.g. "flatpak-spawn --host pdflatex").
fresh
cat > "$T/r/paper/claimtest.tex" <<'TEX'
\documentclass{article}
\input{numbers}
\begin{document}
A40: \claim{singlecomp_cuda_a40_n50000}. Typo: \claim{singlecomp_cuda_a40_n5000O}.
\end{document}
TEX
PDFLATEX=${PDFLATEX:-pdflatex}
if command -v "${PDFLATEX%% *}" >/dev/null 2>&1; then
    (cd "$T/r/paper" && $PDFLATEX -interaction=nonstopmode -halt-on-error claimtest.tex) \
        > "$T/out" 2>&1
    if grep -q "claim singlecomp_cuda_a40_n5000O undefined" "$T/out"; then
        echo "ok    mistyped \\claim id stops the LaTeX build"
    else echo "FAIL  mistyped \\claim id: LaTeX did not stop on it"; tail -20 "$T/out"; fail=1; fi
else
    echo "skip  mistyped \\claim id (no $PDFLATEX)"
fi

cat > "$T/r/paper/linttest.tex" <<'TEX'
\begin{document}
GENESIS~2.5 reaches $\claim{ksweep_e2e_k5000}\times$ in 2026, and $41.7\times$ elsewhere.
\end{document}
TEX
if (cd "$T/r" && python3 reproduce/lint_numbers.py paper/linttest.tex) > "$T/out" 2>&1; then
    echo "FAIL  lint accepted a result typed by hand"; fail=1
elif grep -q "linttest.tex:2: 41.7" "$T/out" && [ "$(grep -c 'linttest.tex' "$T/out")" = 1 ]; then
    echo "ok    lint flags the typed result and nothing else"
else echo "FAIL  lint output"; cat "$T/out"; fail=1; fi

[ "$fail" = 0 ] && echo "all claim-map checks passed"
exit "$fail"
