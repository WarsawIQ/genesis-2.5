#!/bin/sh
# Bring every result produced on the cluster into this checkout.
#
#     sh cluster_bringup/sync_from_cluster.sh             # from the working clone
#     CLUSTER_ROOT=genesis-2.5 sh cluster_bringup/sync_from_cluster.sh
#
# Runs on the machine that holds the repository, not on the cluster. Results
# of the paper were lost before because they stayed on the cluster, printed to
# a terminal or written into a copy nobody collected; this pulls them in after
# every run, and git records them from there.
#
# What it copies, from $CLUSTER_HOST:$CLUSTER_ROOT (a path under the remote
# home directory):
#   cluster_bringup/logs/   new files only; a file that exists here with other
#                           content is never overwritten, only reported
#   reproduce/results/      the pack's output directory, which every run
#                           overwrites; each run is kept as
#                           cluster_bringup/logs/reproduce/umcs_<time of summary.csv>/
#
# It changes nothing on the cluster and commits nothing: review, then commit.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST=${CLUSTER_HOST:-miranda}
REMOTE=${CLUSTER_ROOT:-genesis-2.5-git}
LOGS="$ROOT/cluster_bringup/logs"

ssh -o BatchMode=yes "$HOST" "test -d '$REMOTE/cluster_bringup/logs'" 2>/dev/null \
    || { echo "no $REMOTE/cluster_bringup/logs on $HOST" >&2; exit 1; }

# Only ssh, tar and sha256sum are needed on either side (rsync is not always
# available where the repository is checked out).
remote_sums=$(ssh -o BatchMode=yes "$HOST" \
    "cd '$REMOTE/cluster_bringup/logs' && find . -type f -print0 | xargs -0 sha256sum" 2>/dev/null)

new_files=""; conflicts=""
echo "$remote_sums" | {
    while read -r sum path; do
        [ -n "$path" ] || continue
        rel=${path#./}
        # The .md notes in logs/ are written in the repository, not by runs.
        case "$rel" in *.md) continue ;; esac
        if [ ! -e "$LOGS/$rel" ]; then
            echo "$rel" >> "$LOGS/.sync_new.$$"
        elif [ "$(sha256sum < "$LOGS/$rel" | cut -d' ' -f1)" != "$sum" ]; then
            echo "$rel" >> "$LOGS/.sync_conflict.$$"
        fi
    done
}

echo "== logs: new files from $HOST:$REMOTE =="
if [ -s "$LOGS/.sync_new.$$" ]; then
    tr '\n' '\0' < "$LOGS/.sync_new.$$" \
        | ssh -o BatchMode=yes "$HOST" "cd '$REMOTE/cluster_bringup/logs' && tar cf - --null -T -" 2>/dev/null \
        | (cd "$LOGS" && tar xpf -)
    sed 's/^/  new  /' "$LOGS/.sync_new.$$"
else
    echo "  none"
fi
if [ -s "$LOGS/.sync_conflict.$$" ]; then
    echo "== same name, different content (left as they are here; compare by hand) =="
    sed 's/^/  differs  /' "$LOGS/.sync_conflict.$$"
fi
rm -f "$LOGS/.sync_new.$$" "$LOGS/.sync_conflict.$$"

echo "== reproduce/results =="
stamp=$(ssh -o BatchMode=yes "$HOST" \
    "cd '$REMOTE/reproduce/results' 2>/dev/null && [ -f summary.csv ] \
     && echo umcs_\$(date -r summary.csv +%Y%m%d_%H%M%S)" 2>/dev/null)
if [ -n "$stamp" ]; then
    dest="$LOGS/reproduce/$stamp"
    if [ -d "$dest" ]; then
        echo "  already collected: cluster_bringup/logs/reproduce/$stamp"
    else
        mkdir -p "$dest"
        ssh -o BatchMode=yes "$HOST" "cd '$REMOTE/reproduce/results' && tar cf - ." 2>/dev/null \
            | (cd "$dest" && tar xpf -) \
            && echo "  collected: cluster_bringup/logs/reproduce/$stamp"
    fi
else
    echo "  no reproduce run on $HOST:$REMOTE"
fi

echo
(cd "$ROOT" && git status --short -- cluster_bringup/logs | head -40)
