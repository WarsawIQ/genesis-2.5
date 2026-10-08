#!/bin/sh
# Run spike_start_check.sh on a released build and on a fix, on one node.
#
#     sh cluster_bringup/campaign/before_after_check.sh <before checkout|-> <fix checkout>
#
# <before checkout> must already be built (prepare_node.sh); "-" skips it.
# <fix checkout> is built here with CAMPAIGN_DRY=1 (a dirty or untagged tree
# is allowed, so these numbers are evidence for the fix, not campaign numbers)
# and then checked. Each spike_start_check.sh writes its own log under its
# checkout's logs/campaign_prep/; copy those into the repo. SCALE and TMAX pass
# through to spike_start_check.sh, and WORK_DIR (the toolchains, as for
# prepare_node.sh) must be set. Run it detached on the GPU node, e.g.
#
#     WORK_DIR=<toolchains> setsid nohup sh before_after_check.sh <release> <fix> \
#         > <log> 2>&1 < /dev/null &
set -u
[ $# -eq 2 ] || { echo "usage: $0 <before checkout|-> <fix checkout>" >&2; exit 2; }
[ -n "${WORK_DIR:-}" ] || { echo "set WORK_DIR to the toolchains (see prepare_node.sh)" >&2; exit 2; }
export WORK_DIR
if [ "$1" != - ]; then
    echo "=== BEFORE: $1 ($(cd "$1" && git describe --tags --always))"
    ( cd "$1" && sh cluster_bringup/campaign/spike_start_check.sh ); echo "exit $?"
fi
echo "=== building the fix: $2 ($(cd "$2" && git describe --tags --always))"
( cd "$2" && CAMPAIGN_DRY=1 sh cluster_bringup/campaign/prepare_node.sh > "$2/../$(basename "$2")-build.log" 2>&1 )
echo "build exit $?"
echo "=== AFTER: the fix"
( cd "$2" && sh cluster_bringup/campaign/spike_start_check.sh ); echo "exit $?"
echo "=== ALL DONE"
