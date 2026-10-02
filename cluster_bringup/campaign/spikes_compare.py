#!/usr/bin/env python3
"""Compare spike trains of the same network computed different ways (E5).

    python3 cluster_bringup/campaign/spikes_compare.py <out.csv> <ncells> \\
        <tstop_s> <ref label>=<file> <label>=<file> ...

Each file is a GENESIS spikehistory file: one line per spike, "<cell> <time s>".
The first file is the reference (the fp64 CPU solver). For every file this
reports the spike count, the mean rate per cell, the distribution of
inter-spike intervals (mean, CV, median, 5th and 95th percentiles), and,
against the reference:

- the time of first divergence: spikes are ordered by (time, cell) and
  compared one by one; the first pair that differs in cell or by more than
  half a time step (25 us) in time marks it. Before that time the two runs
  are spike-for-spike identical; after it they are chaotic network
  trajectories that can only be compared statistically;
- the Kolmogorov-Smirnov distance between the pooled ISI distributions;
- the difference in total spike count and the correlation of per-cell counts.

Writes one row per file to out.csv and prints a table. Plain Python 3.6.
"""

import csv
import math
import sys

TOL_S = 25e-6   # half of dt = 0.05 ms


def load(path):
    spikes = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) >= 2:
                try:
                    spikes.append((float(p[-1]), int(float(p[0]))))
                except ValueError:
                    pass
    spikes.sort()
    return spikes


def isis(spikes):
    last, out = {}, []
    for t, c in spikes:
        if c in last:
            out.append(t - last[c])
        last[c] = t
    out.sort()
    return out


def pct(xs, q):
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * q
    i = int(k)
    return xs[i] if i + 1 >= len(xs) else xs[i] + (xs[i + 1] - xs[i]) * (k - i)


def ks(a, b):
    if not a or not b:
        return float("nan")
    i = j = 0
    d = 0.0
    while i < len(a) and j < len(b):
        x = min(a[i], b[j])          # step both empirical CDFs past x, ties included
        while i < len(a) and a[i] <= x:
            i += 1
        while j < len(b) and b[j] <= x:
            j += 1
        d = max(d, abs(i / len(a) - j / len(b)))
    return d


def first_divergence(ref, other):
    for k, ((t1, c1), (t2, c2)) in enumerate(zip(ref, other)):
        if c1 != c2 or abs(t1 - t2) > TOL_S:
            return min(t1, t2), k
    if len(ref) != len(other):
        k = min(len(ref), len(other))
        return (ref[k][0] if len(ref) > k else other[k][0]), k
    return None, len(ref)


def per_cell(spikes, ncells):
    n = [0] * ncells
    for _, c in spikes:
        if 0 <= c < ncells:
            n[c] += 1
    return n


def corr(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    sa = math.sqrt(sum((x - ma) ** 2 for x in a))
    sb = math.sqrt(sum((y - mb) ** 2 for y in b))
    if sa == 0 or sb == 0:
        return float("nan")
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / (sa * sb)


def main(argv):
    if len(argv) < 5:
        print(__doc__.strip().split("\n")[2].strip(), file=sys.stderr)
        return 2
    out, ncells, tstop = argv[0], int(argv[1]), float(argv[2])
    runs = [a.split("=", 1) for a in argv[3:]]
    ref_label, ref = runs[0][0], load(runs[0][1])
    ref_isi = isis(ref)
    ref_cells = per_cell(ref, ncells)
    rows = []
    for label, path in runs:
        s = load(path)
        i = isis(s)
        mean = sum(i) / len(i) if i else float("nan")
        cv = (math.sqrt(sum((x - mean) ** 2 for x in i) / (len(i) - 1)) / mean
              if len(i) > 1 else float("nan"))
        t_div, k_div = first_divergence(ref, s)
        rows.append({
            "run": label, "file": path, "spikes": len(s),
            "rate_hz": "%.4f" % (len(s) / ncells / tstop),
            "isi_mean_ms": "%.4f" % (mean * 1e3), "isi_cv": "%.4f" % cv,
            "isi_median_ms": "%.4f" % (pct(i, 0.5) * 1e3),
            "isi_p05_ms": "%.4f" % (pct(i, 0.05) * 1e3),
            "isi_p95_ms": "%.4f" % (pct(i, 0.95) * 1e3),
            "vs": ref_label,
            "identical": "yes" if t_div is None else "no",
            "first_divergence_s": "" if t_div is None else "%.6f" % t_div,
            "spikes_identical_before": k_div,
            "count_diff_pct": "%.4f" % ((len(s) - len(ref)) / len(ref) * 100 if ref else float("nan")),
            "ks_isi": "%.5f" % ks(ref_isi, i),
            "cell_count_corr": "%.5f" % corr(ref_cells, per_cell(s, ncells)),
        })
    with open(out, "w") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("%-14s %9s %8s %8s %6s %10s %8s %8s" % (
        "run", "spikes", "rate Hz", "ISI ms", "CV", "diverges s", "KS", "count %"))
    for r in rows:
        print("%-14s %9d %8s %8s %6s %10s %8s %8s" % (
            r["run"], r["spikes"], r["rate_hz"], r["isi_mean_ms"], r["isi_cv"],
            r["first_divergence_s"] or "never", r["ks_isi"], r["count_diff_pct"]))
    print("written: " + out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
