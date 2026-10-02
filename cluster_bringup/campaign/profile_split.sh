#!/bin/sh
# profile_split.sh <perf.data> <out prefix>: the profile as symbol percentages
# (<out>_symbols.txt, every symbol) and as the E6 categories (<out>_categories.csv),
# using profile_categories.txt.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
perf report -i "$1" --stdio --no-children --sort symbol 2>/dev/null \
    | grep -E "^ +[0-9.]+%" > "$2_symbols.txt"
awk -v map="$HERE/profile_categories.txt" '
    BEGIN { FS = "\t"; while ((getline l < map) > 0) { if (l ~ /^#/ || l == "") continue
            split(l, a, "\t"); n++; re[n] = a[1]; cat[n] = a[2] } FS = " " }
    { pct = $1 + 0; sym = ""
      for (i = 2; i <= NF; i++) if ($i ~ /^\[/) { sym = $(i + 1); break }
      if (sym == "") sym = $NF
      c = "other"; for (k = 1; k <= n; k++) if (sym ~ re[k]) { c = cat[k]; break }
      t[c] += pct; tot += pct }
    END { print "category,percent"; for (c in t) printf "%s,%.2f\n", c, t[c]
          printf "total,%.2f\n", tot }' "$2_symbols.txt" > "$2_categories.csv"
cat "$2_categories.csv"
