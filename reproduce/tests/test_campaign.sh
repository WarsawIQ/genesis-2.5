#!/bin/sh
# The campaign harness must refuse what would make a number untrustworthy.
# Each case runs a toy stage on top of cluster_bringup/campaign/lib.sh in a
# throw-away copy of the repository, with a stub in place of nvidia-smi, and
# checks that it refuses, rejects or resumes as the harness contract says.
# Needs no GPU.
#
#     sh reproduce/tests/test_campaign.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/campaign_test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; [ -f "$T/out" ] && tail -15 "$T/out"; fail=1; }

# A stub nvidia-smi: the card is busy when $T/busy exists.
cat > "$T/nvsmi" <<'EOF'
#!/bin/sh
B=$(dirname "$0")/busy
case "$*" in
  -L) echo "GPU 0: Stub (UUID: GPU-0)" ;;
  *query-compute-apps*) [ -f "$B" ] && echo "4242, python, 29000 MiB" ;;
  *memory.used*) [ -f "$B" ] && echo 29000 || echo 0 ;;
  *name*) echo "Stub GPU" ;;
  *driver_version*) echo 1.0 ;;
  *persistence_mode*) echo Enabled ;;
  *clocks.sm*) echo "210, 1410" ;;
  *) echo x ;;
esac
EOF
chmod +x "$T/nvsmi"

fresh() {
    rm -rf "$T/r"; mkdir -p "$T/r"
    (cd "$ROOT" && git ls-files -co --exclude-standard | tar cf - -T -) | (cd "$T/r" && tar xf -)
    (cd "$T/r" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm t) \
        || { echo "cannot make a git copy"; exit 1; }
    rm -f "$T/busy"
}

# A toy stage: two arms, $REPS replicates. The command prints the banner given
# in BANNER_OUT, sleeps SLEEP seconds and prints a result line. FAIL_ONCE names
# an "arm:rep" whose first attempt exits 1; BUSY_DURING makes the card busy
# while that arm runs.
cat > "$T/stage.sh" <<'EOF'
. "$GENESIS_ROOT/cluster_bringup/campaign/lib.sh"
. "$GENESIS_ROOT/cluster_bringup/campaign/sanity.sh"
toy() {
    want="${WANT:-fp32 kernels}"
    run_rep "$1" "$2" "$3" 1 "$want" sanity_grep \
        sh -c 'echo "CUDA: ready (10 compartments, 1 chips, ${BANNER_OUT:-fp32} kernels)"
               [ "${BUSY_DURING:-}" = "$0" ] && touch "$STUBDIR/busy"
               if [ "${FAIL_ONCE:-}" = "$0:$1" ] && [ ! -f "$STUBDIR/failed_once" ]; then
                   touch "$STUBDIR/failed_once"; exit 1; fi
               sleep ${SLEEP:-0.6}; echo "RESULT_T_PER_STEP= 0.001"' "$1" "$2"
}
SANITY_RE='^RESULT_T_PER_STEP=' SANITY_METRIC=t_per_step_s
export SANITY_RE SANITY_METRIC
campaign_init EX
run_arms "${REPS:-2}" toy armA armB; st=$?
campaign_done "$st" "a_over_b=armA/armB"
exit $st
EOF

stage() {   # runs the toy stage in the copy; exit code returned
    (cd "$T/r" && env GENESIS_ROOT="$T/r" NVIDIA_SMI="$T/nvsmi" STUBDIR="$T" \
        CAMPAIGN_WAIT_S=0 CAMPAIGN_WAIT_TRIES=2 CAMPAIGN_NODE=testnode "$@" \
        sh "$T/stage.sh") > "$T/out" 2>&1
}
OUTDIR="$T/r/cluster_bringup/logs/campaign_dry"
csv() { ls "$OUTDIR"/EX_testnode_*.csv 2>/dev/null | grep -v report | head -1; }

# 1. Only the tag, and only a clean tree
fresh
stage; rc=$?
if [ "$rc" = 2 ] && grep -q "REFUSED" "$T/out"; then ok "untagged checkout refused"
else bad "untagged checkout: rc $rc"; fi

# 2. A clean dry run: warm-ups, interleaved replicates, header, report
fresh
stage CAMPAIGN_DRY=1; rc=$?
C=$(csv)
if [ "$rc" = 0 ] && [ "$(grep -c ',ok,' "$C")" = 6 ] \
   && grep -q "^# commit: " "$C" && grep -q "^# gpu: Stub GPU" "$C" \
   && [ "$(grep ',1,[12],' "$C" | grep -c ',ok,')" = 2 ] \
   && grep -q ",EX,armB,1,1," "$C" && grep -q ",EX,armA,2,1," "$C" \
   && [ ! -f "$OUTDIR/EX_testnode.open" ] && grep -q "a_over_b" "${C%.csv}_report.md"; then
    ok "dry run: 2 warm-ups + 4 replicates, rotated order, header, report with ratio"
else bad "dry run: rc $rc"; [ -n "$C" ] && cat "$C"; fi

# 3. A busy card: wait, retry, give up with 3, name the process
fresh; touch "$T/busy"
stage CAMPAIGN_DRY=1; rc=$?
if [ "$rc" = 3 ] && grep -q "4242, python" "$OUTDIR/busy.log" && [ "$(grep -c ',ok,' "$(csv)")" = 0 ]; then
    ok "busy GPU: waited, gave up with exit 3, logged the foreign process"
else bad "busy GPU: rc $rc"; fi

# 4. Wrong precision in the banner: rejected, retried once, exit 4
fresh
stage CAMPAIGN_DRY=1 WANT="fp64 kernels" REPS=1; rc=$?
if [ "$rc" = 4 ] && grep -q "banner does not match" "$OUTDIR/rejected.csv" \
   && [ "$(grep -c ',ok,' "$(csv)")" = 0 ]; then
    ok "banner mismatch (fp32 binary, fp64 asked): every run rejected"
else bad "banner mismatch: rc $rc"; fi

# 5. Implausibly fast run: rejected by the sanity band
fresh
stage CAMPAIGN_DRY=1 SLEEP=0 REPS=1; rc=$?
if [ "$rc" = 4 ] && grep -q "outside the plausible band" "$OUTDIR/rejected.csv"; then
    ok "a run that finished in no time is rejected"
else bad "fast run: rc $rc"; fi

# 6. Card taken during a run: that run is rejected
fresh
stage CAMPAIGN_DRY=1 BUSY_DURING=armB REPS=1; rc=$?
if grep -q "GPU busy after the run" "$OUTDIR/rejected.csv" && [ "$rc" = 3 ]; then
    ok "a foreign job during the run rejects the run, then the stage stops with 3"
else bad "busy during run: rc $rc"; fi

# 7. A failed run is retried once and the stage completes
fresh; rm -f "$T/failed_once"
stage CAMPAIGN_DRY=1 FAIL_ONCE=armA:1 REPS=1; rc=$?
if [ "$rc" = 0 ] && grep -q "exit code 1" "$OUTDIR/rejected.csv" && [ "$(grep -c ',ok,' "$(csv)")" = 4 ]; then
    ok "a failed run is retried and replaced"
else bad "retry: rc $rc"; fi

# 8. Resume: a stopped session continues in the same session, no duplicates
fresh; touch "$T/busy"
stage CAMPAIGN_DRY=1 REPS=2 >/dev/null; first=$(csv)
rm -f "$T/busy"
stage CAMPAIGN_DRY=1 REPS=2; rc=$?
if [ "$rc" = 0 ] && [ "$(csv)" = "$first" ] && [ "$(ls "$OUTDIR"/EX_testnode_*.csv | grep -vc report)" = 1 ] \
   && grep -q "^# resumed: " "$first" && [ "$(grep -c ',ok,' "$first")" = 6 ]; then
    ok "resume: same session, same file, every replicate once"
else bad "resume: rc $rc"; fi

# 9. A changed source refuses; a file the build regenerates does not
fresh
echo "/* changed */" >> "$T/r/genesis/src/hines/hines_solve.c"
stage CAMPAIGN_TAG=t; rc=$?
(cd "$T/r" && git checkout -q -- genesis/src/hines/hines_solve.c && git tag t)
echo "/* regenerated */" >> "$T/r/genesis/src/hines/hines_d@.c"
stage CAMPAIGN_TAG=t REPS=1; rc2=$?
if [ "$rc" = 2 ] && [ "$rc2" = 0 ] \
   && grep -q "^# build_generated_changed: 1" "$T/r/cluster_bringup/logs/campaign_t"/EX_testnode_*.csv; then
    ok "a changed source refuses; a regenerated build file is allowed and counted"
else bad "dirty check: rc $rc then $rc2"; fi

[ "$fail" = 0 ] && echo "all campaign harness checks passed"
exit "$fail"
