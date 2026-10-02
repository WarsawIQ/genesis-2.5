#!/usr/bin/env python3
"""Write the report of one campaign session next to its CSV.

    python3 cluster_bringup/campaign/report.py <E?_<session>.csv> [ratio ...]

A ratio is "name=numerator_arm/denominator_arm"; each one is reported as the
ratio of the arms' means with the relative sample SDs combined in quadrature,
the one uncertainty definition used everywhere in the paper.

The report gives, per arm: valid runs, mean, sample SD, relative SD, min, max,
and the rejected runs with their reasons. Warm-up runs (rep 0) are listed but
never averaged. An arm with fewer valid replicates than the most complete arm
is marked incomplete and is not used in a ratio; an RSD above 5% is flagged
(SC-004 of the campaign spec). A notes file in the session's run folder, if
the operator wrote one, is appended verbatim.

Exit 1 if the CSV has no header or names a different commit than the other
sessions of the same experiment in the folder. Plain Python 3.6.
"""

import csv
import glob
import math
import os
import sys


def read(path):
    head, rows = {}, []
    with open(path) as f:
        body = []
        for line in f:
            if line.startswith("# "):
                k, _, v = line[2:].partition(": ")
                head.setdefault(k.strip(), v.strip())
            else:
                body.append(line)
    rows = list(csv.DictReader(body))
    return head, rows


def stats(xs):
    n = len(xs)
    m = sum(xs) / n
    sd = math.sqrt(sum((x - m) ** 2 for x in xs) / (n - 1)) if n > 1 else float("nan")
    return n, m, sd


def main(argv):
    if not argv:
        print(__doc__.strip().split("\n")[2].strip(), file=sys.stderr)
        return 2
    path = argv[0]
    head, rows = read(path)
    if "commit" not in head:
        print("report: %s has no run header" % path, file=sys.stderr)
        return 1
    exp = head.get("experiment", "?")
    for other in glob.glob(os.path.join(os.path.dirname(path) or ".", exp + "_*.csv")):
        oh, _ = read(other)
        if oh.get("commit") and oh["commit"] != head["commit"]:
            print("report: %s is from commit %s, %s from %s" % (
                other, oh["commit"][:10], path, head["commit"][:10]), file=sys.stderr)
            return 1

    arms = []
    for r in rows:
        if r["arm"] not in arms:
            arms.append(r["arm"])
    valid = {a: [float(r["wall_s"]) for r in rows
                 if r["arm"] == a and r["status"] == "ok" and r["rep"] != "0"] for a in arms}
    full = max((len(v) for v in valid.values()), default=0)

    out = ["# %s, session %s" % (exp, head.get("session", "?")), ""]
    out.append("Commit `%s` (%s%s), node %s, %s." % (
        head["commit"][:12], head.get("describe", "?"),
        "" if head.get("dirty", "0") == "0" else ", %s changed files" % head.get("dirty"),
        head.get("node", "?"), head.get("gpu", "no GPU")))
    out.append("Clocks before: %s MHz; after: %s MHz. Complete: %s." % (
        head.get("sm_clock_mhz", "-"), head.get("sm_clock_mhz_after", "-"),
        head.get("complete", "no (session still open)")))
    out.append("")
    out.append("| Arm | n | Mean (s) | SD (s) | RSD | Min | Max | Rejected | Note |")
    out.append("|---|---:|---:|---:|---:|---:|---:|---:|---|")
    means = {}
    for a in arms:
        rej = [r for r in rows if r["arm"] == a and r["status"] != "ok"]
        xs = valid[a]
        if not xs:
            out.append("| %s | 0 | | | | | | %d | no valid run |" % (a, len(rej)))
            continue
        n, m, sd = stats(xs)
        rsd = sd / m * 100 if n > 1 else float("nan")
        note = []
        if n < full:
            note.append("incomplete")
        else:
            means[a] = (m, sd)
        if rsd == rsd and rsd > 5:
            note.append("RSD > 5%")
        out.append("| %s | %d | %.3f | %.3f | %.1f%% | %.3f | %.3f | %d | %s |" % (
            a, n, m, sd, rsd, min(xs), max(xs), len(rej), ", ".join(note)))

    ratios = [x for x in argv[1:] if "=" in x and "/" in x]
    if ratios:
        out += ["", "| Ratio | Value | ± |", "|---|---:|---:|"]
        for spec in ratios:
            name, _, expr = spec.partition("=")
            num, _, den = expr.partition("/")
            if num in means and den in means:
                (a, sa), (b, sb) = means[num], means[den]
                v = a / b
                u = v * math.sqrt((sa / a) ** 2 + (sb / b) ** 2)
                out.append("| %s (%s / %s) | %.3f | %.3f |" % (name, num, den, v, u))
            else:
                out.append("| %s (%s / %s) | not computed: an arm is missing or incomplete | |"
                           % (name, num, den))

    rejected = [r for r in rows if r["status"] != "ok"]
    if rejected:
        out += ["", "Rejected runs:", ""]
        for r in rejected:
            out.append("- %s rep %s: %s" % (r["arm"], r["rep"], r["status"]))
    warm = [r for r in rows if r["rep"] == "0" and r["status"] == "ok"]
    if warm:
        out += ["", "Warm-up runs (not averaged): " + ", ".join(
            "%s %.2f s" % (r["arm"], float(r["wall_s"])) for r in warm)]

    notes = os.path.join(os.path.dirname(path), "runs", head.get("session", ""), "notes")
    if os.path.isfile(notes):
        out += ["", "Operator notes:", "", open(notes).read().rstrip()]

    dest = path[:-4] + "_report.md"
    with open(dest, "w") as f:
        f.write("\n".join(out) + "\n")
    print("report: " + dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
