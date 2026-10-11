#!/bin/sh
# Before the upstream pull request: build GENESIS 2.4 and the branch with the CPU
# fixes in fresh copies and run the branch's tests on both.
#
#     sh cluster_bringup/campaign/upstream_pr_check.sh <upstream worktree> [<base> [<branch>]]
#
# <upstream worktree> is a clone of genesis-sim/genesis-2.4 holding the branch
# (upstream-cpu-fixes by default) on top of <base> (7b0a66b, 2.4 as of May
# 2019). Both are taken with git archive into a new directory next to this
# repository, the branch's tests are copied into the base, and each is built
# CPU-only and runs genesis/Scripts/tests/run_hsolve_tests.sh (one hsolve over
# 1 and 8 cells, backward Euler and Crank-Nicolson, against a single-cell
# reference) and run_construction_test.sh (construction time against model
# size). On the base the 8-cell cases must fail and construction grow faster
# than linearly; on the branch everything must pass and grow linearly.
#
# Writes logs/campaign_prep/upstream_pr_check_<host>_<time>.log.
set -u
[ $# -ge 1 ] || { echo "usage: $0 <upstream worktree> [<base> [<branch>]]" >&2; exit 2; }
W=$(cd "$1" && pwd); BASE=${2:-7b0a66b}; BR=${3:-upstream-cpu-fixes}
GENESIS_ROOT=${GENESIS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
STAMP=$(hostname -s)_$(date +%Y%m%d_%H%M%S)
C=$(dirname "$GENESIS_ROOT")/upstream-pr-check-$STAMP
LOG=$GENESIS_ROOT/cluster_bringup/logs/campaign_prep/upstream_pr_check_$STAMP.log
mkdir -p "$C" "$(dirname "$LOG")"
{
echo "# $(hostname -s), $(gcc --version | head -1); base $(git -C "$W" rev-parse "$BASE"), branch $BR $(git -C "$W" rev-parse "$BR")"
for v in base fixes; do
    D=$C/$v; mkdir -p "$D"
    if [ $v = base ]; then
        git -C "$W" archive "$BASE" | tar -x -C "$D"
        git -C "$W" archive "$BR" genesis/Scripts/tests | tar -x -C "$D"
    else
        git -C "$W" archive "$BR" | tar -x -C "$D"
    fi
    mkdir -p "$D/locallib"; printf 'int yywrap(void){return 1;}\n' > "$D/locallib/yywrap.c"
    gcc -c "$D/locallib/yywrap.c" -o "$D/locallib/yywrap.o" && ar rcs "$D/locallib/libfl.a" "$D/locallib/yywrap.o"
    ( cd "$D/genesis/src" && ./configure > ../../configure.log 2>&1 \
      && make CC="gcc -std=gnu89" TERMCAP="-lncurses -ltinfo" LEXLIB="$D/locallib/libfl.a" nxgenesis > ../../make.log 2>&1 )
    echo "== $v: build exit $?"
    ( cd "$D" && sh genesis/Scripts/tests/run_hsolve_tests.sh ./genesis/src/nxgenesis; echo "hsolve tests exit $?" )
    ( cd "$D" && MODE=create sh genesis/Scripts/tests/run_construction_test.sh ./genesis/src/nxgenesis 1000 2000 4000 8000 )
done
echo "built in $C"
} 2>&1 | tee "$LOG"
echo "written: $LOG"
