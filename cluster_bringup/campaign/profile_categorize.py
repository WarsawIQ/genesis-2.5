#!/usr/bin/env python3
"""Sum a perf profile, reported by library and symbol, into the E6 categories.

    python3 cluster_bringup/campaign/profile_categorize.py <map> <arm>_dso_symbols.txt > <arm>_categories.csv

<arm>_dso_symbols.txt is `perf report --stdio --no-children --sort dso,symbol`
as profile_dso.sh keeps it. <map> holds one extended regular expression, a
TAB and a category per line (profile_categories_dso.txt); each sample's
"<library>:<symbol>" takes the category of the first pattern that matches,
and "other" if none does. Writes category,percent,symbols (how many distinct
symbols fell into it), the categories in descending order, then total.
Plain Python 3.6.
"""

import re
import sys

LINE = re.compile(r"^\s*([\d.]+)%\s+(\S+)\s+\[.\]\s+(.*?)\s+-\s+-\s*$")


def main(map_path, prof_path):
    rules = []
    with open(map_path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            pattern, category = line.split("\t")
            rules.append((re.compile(pattern), category))
    share, count, total = {}, {}, 0.0
    with open(prof_path, errors="replace") as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            pct, lib, sym = float(m.group(1)), m.group(2), m.group(3)
            key = "%s:%s" % (lib, sym)
            cat = next((c for r, c in rules if r.search(key)), "other")
            share[cat] = share.get(cat, 0.0) + pct
            count[cat] = count.get(cat, 0) + 1
            total += pct
    print("category,percent,symbols")
    for cat in sorted(share, key=lambda c: -share[c]):
        print("%s,%.2f,%d" % (cat, share[cat], count[cat]))
    print("total,%.2f,%d" % (total, sum(count.values())))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
