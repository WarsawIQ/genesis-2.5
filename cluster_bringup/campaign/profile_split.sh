#!/bin/sh
# profile_split.sh <perf.data> <out prefix>: the profile as text, then its E6
# categories.
#   <out>_symbols.txt       perf report --sort symbol (every symbol)
#   <out>_dso.txt           perf report --sort dso (every library)
#   <out>_dso_symbols.txt   perf report --sort dso,symbol
#   <out>_categories.csv    profile_categorize.py with profile_categories_dso.txt
# The reports are what a reader needs to re-bucket the profile; perf.data
# itself is large and is not kept. Until v2.6.0-rc3 only the symbol report was
# kept and the categories came from profile_categories.txt, which matched
# symbols alone and missed most of both simulators' time.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
for s in symbol dso dso,symbol; do
    case "$s" in symbol) o=symbols ;; dso) o=dso ;; *) o=dso_symbols ;; esac
    perf report -i "$1" --stdio --no-children --sort "$s" 2>/dev/null \
        | grep -E "^ +[0-9.]+%" > "$2_$o.txt"
done
python3 "$HERE/profile_categorize.py" "$HERE/profile_categories_dso.txt" "$2_dso_symbols.txt" \
    > "$2_categories.csv"
cat "$2_categories.csv"
