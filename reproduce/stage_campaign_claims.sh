#!/bin/sh
# Bring the campaign's numbers into the claim map, the morning after a night:
#
#     sh cluster_bringup/sync_from_cluster.sh      # the data arrive
#     sh reproduce/stage_campaign_claims.sh        # this script
#     python3 reproduce/make_numbers.py            # the numbers reach the paper
#
# reproduce/claims_campaign_staged.csv holds the claim rows written before the
# campaign, with {{E2_INF02}}-style placeholders where the session file's name
# belongs (the name carries the session's timestamp, unknown until it runs);
# {{SPK:E5_INF03}} names that session's spike comparison (spikes_compare.py);
# {{SUF:E6_INF03:_g_spk_categories.csv}} names the file the session wrote under
# its own name with that suffix.
# This script finds each experiment's session CSV under the campaign folder,
# derives its tidy table (cluster_bringup/campaign/tidy.py), substitutes the
# paths and session ids, and appends the rows whose data exist to
# reproduce/claims.csv. Rows whose placeholders have no data yet are left for
# the next morning; an id already in claims.csv is skipped if identical and
# refused otherwise. Then switch each \pending{id} to \claim{id} in the
# manuscript; the lint lists what is still open.
#
# After a new night on a new tag (CAMPAIGN_LOGS pointing at its folder):
#
#     sh reproduce/stage_campaign_claims.sh --restage
#
# first takes every staged id out of claims.csv, then stages them all from the
# new sessions, so no number of the old night survives. It refuses unless every
# experiment of the staged file has its session there.
set -u
RESTAGE=0; [ "${1:-}" = --restage ] && RESTAGE=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CAMPAIGN_LOGS=${CAMPAIGN_LOGS:-$ROOT/cluster_bringup/logs/campaign_v2.6.0-rc4}
CLAIMS=${CLAIMS:-$ROOT/reproduce/claims.csv}
STAGED="$ROOT/reproduce/claims_campaign_staged.csv"
T=$(mktemp "${TMPDIR:-/tmp}/staged.XXXXXX")
trap 'rm -f "$T" "$T.sed" "$T.ids" "$T.keep"' EXIT

: > "$T.sed"
missing=""
for tok in $(grep -o '{{[A-Z]*:\{0,1\}[A-Za-z0-9]*_[A-Z0-9]*}}' "$STAGED" | sed 's/^{{[A-Z]*:/{{/' | sort -u | tr -d '{}'); do
    exp=${tok%_*}; node=$(echo "${tok##*_}" | tr 'A-Z' 'a-z')
    set -- $(ls "$CAMPAIGN_LOGS/${exp}_${node}_"*.csv 2>/dev/null | grep -E "/${exp}_${node}_[0-9]{8}_[0-9]{6}\.csv\$")
    if [ $# -eq 0 ]; then missing="$missing $tok"; continue; fi
    [ $# -eq 1 ] || { echo "REFUSED: $# session files for $tok in $CAMPAIGN_LOGS -- one session"\
                           "per experiment and node; mark the stale one superseded first" >&2; exit 1; }
    tidy=$(python3 "$ROOT/cluster_bringup/campaign/tidy.py" "$1" | cut -d: -f1)
    rel=${tidy#"$ROOT"/}
    sess=$(basename "$1" .csv); sess=${sess#"${exp}"_}
    printf 's|{{%s}}|%s|g\ns|{{S:%s}}|%s|g\n' "$tok" "$rel" "$tok" "$sess" >> "$T.sed"
    spk=${1%.csv}_spikes.csv
    [ -f "$spk" ] && printf 's|{{SPK:%s}}|%s|g\n' "$tok" "${spk#"$ROOT"/}" >> "$T.sed"
    base=${1%.csv}
    for suf in $(grep -o "{{SUF:$tok:[^}]*}}" "$STAGED" | sed "s/^{{SUF:$tok://; s/}}\$//" | sort -u); do
        [ -f "$base$suf" ] && printf 's|{{SUF:%s:%s}}|%s|g\n' "$tok" "$suf" "${base#"$ROOT"/}$suf" >> "$T.sed"
    done
done

if [ "$RESTAGE" = 1 ]; then
    [ -z "$missing" ] || { echo "REFUSED: --restage needs every experiment; no session for:$missing" >&2; exit 1; }
    tail -n +2 "$STAGED" | cut -d, -f1 | sed 's/^/^/; s/$/,/' > "$T.ids"
    grep -v -f "$T.ids" "$CLAIMS" > "$T.keep" || true
    echo "restage: took $(($(wc -l < "$CLAIMS") - $(wc -l < "$T.keep"))) staged rows out of $(basename "$CLAIMS")"
    cat "$T.keep" > "$CLAIMS"
fi

added=0; skipped=0
sed -f "$T.sed" "$STAGED" | tail -n +2 > "$T"
while IFS= read -r line; do
    case "$line" in *"{{"*) continue ;; esac          # its data are not here yet
    id=${line%%,*}
    have=$(grep "^$id," "$CLAIMS" || true)
    if [ -n "$have" ]; then
        [ "$have" = "$line" ] && { skipped=$((skipped + 1)); continue; }
        echo "REFUSED: $id is already in claims.csv with different content" >&2; exit 1
    fi
    echo "$line" >> "$CLAIMS"; added=$((added + 1))
done < "$T"

echo "added $added claim rows, $skipped already present${missing:+; waiting for data:$missing}"
[ "$added" -gt 0 ] && echo "now: python3 reproduce/make_numbers.py, then \\pending{id} -> \\claim{id} in the manuscript"
exit 0
