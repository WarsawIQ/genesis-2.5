#!/usr/bin/env python3
"""The revised manuscript's measured figures, drawn from the campaign's data.

    python3 paper/scripts/plot_campaign_figures.py \
        [--campaign cluster_bringup/logs/campaign_v2.6.0-rc2] [--out paper/figures]

Reads every E2, E3, E3c and E4 session CSV in the campaign folder (the format of
cluster_bringup/campaign/lib.sh: '# key: value' header lines, then one row per
run) and writes:

    fig_runlength.pdf     E2: end-to-end speedup against run length, fp32 and
                          fp64, one line per card and precision
    fig_trees.pdf         E3: dendritic-tree speedup against population size,
                          end to end (wall clock) and step phase (the solver's
                          own timer), CUDA and OpenCL, per card
    fig_crossover.pdf     E4: GENESIS fp32, GENESIS fp64 and Arbor wall time
                          against run length, one panel per card
    fig_construction.pdf  E3c: construction time against model size, with the
                          pre-fix curve from experiments/data/ (August 2026)

Only rows with status "ok" and rep >= 1 count; a warm-up or rejected run never
reaches a figure. Points are means over replicates with sample-SD error bars.
Exits 2 if an experiment has no data yet, naming it, so a half-finished
campaign cannot silently produce half-finished figures.
"""

import argparse
import csv
import glob
import math
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, LogLocator


def plain_log(ax, axis="y"):
    """Log axis with ticks written as plain numbers (2, 5, 10), not 2x10^0."""
    a = ax.yaxis if axis == "y" else ax.xaxis
    a.set_major_locator(LogLocator(base=10, subs=(1, 2, 5)))
    a.set_minor_formatter(FuncFormatter(lambda v, _: ""))
    a.set_major_formatter(FuncFormatter(lambda v, _: ("%g" % v)))

INK = "#222222"
CARD_COLOR = {"A40": "#1e7f4f", "A100": "#345995"}
ARBOR_COLOR = "#9c5315"


def read_sessions(folder, exp):
    """[(header dict, rows)] for every session CSV of one experiment."""
    out = []
    for path in sorted(glob.glob(os.path.join(folder, exp + "_*.csv"))):
        if path.endswith("_spikes.csv"):
            continue
        head, body = {}, []
        with open(path) as f:
            for line in f:
                if line.startswith("# "):
                    k, _, v = line[2:].partition(": ")
                    head.setdefault(k.strip(), v.strip())
                else:
                    body.append(line)
        rows = [r for r in csv.DictReader(body)
                if r.get("status") == "ok" and r.get("rep") not in ("0", "", None)]
        if rows:
            out.append((head, rows))
    return out


def card(head):
    g = head.get("gpu", "")
    for name in CARD_COLOR:
        if name in g:
            return name
    return g or head.get("node", "?")


def stats(xs):
    n = len(xs)
    m = sum(xs) / n
    sd = math.sqrt(sum((x - m) ** 2 for x in xs) / (n - 1)) if n > 1 else 0.0
    return m, sd


def arm_series(rows, pattern, field="wall_s"):
    """{captured int: (mean, sd)} over arms matching pattern, e.g. r'g32_k(\\d+)$'."""
    acc = {}
    for r in rows:
        m = re.match(pattern, r["arm"])
        if m:
            acc.setdefault(int(m.group(1)), []).append(float(r[field]))
    return {k: stats(v) for k, v in sorted(acc.items())}


def ratio_series(num, den):
    """num/den per shared key, SDs combined in quadrature (the paper's one rule)."""
    out = {}
    for k in num:
        if k in den and den[k][0] > 0 and num[k][0] > 0:
            v = num[k][0] / den[k][0]
            u = v * math.sqrt((num[k][1] / num[k][0]) ** 2 + (den[k][1] / den[k][0]) ** 2)
            out[k] = (v, u)
    return out


def errplot(ax, series, label, color, ls="-", marker="o"):
    ks = sorted(series)
    ax.errorbar(ks, [series[k][0] for k in ks], yerr=[series[k][1] for k in ks],
                label=label, color=color, ls=ls, marker=marker, ms=4, lw=1.4, capsize=2)


def fig_runlength(sessions, dest):
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    for head, rows in sessions:
        c = card(head)
        cpu = arm_series(rows, r"cpu_k(\d+)$")
        for pat, ls, tag in ((r"g32_k(\d+)$", "-", "fp32"), (r"g64_k(\d+)$", "--", "fp64")):
            s = ratio_series(cpu, arm_series(rows, pat))
            if s:
                errplot(ax, s, "%s %s" % (c, tag), CARD_COLOR.get(c, INK), ls=ls)
    ax.set_xscale("log")
    ax.set_xlabel("simulation steps $K$")
    ax.set_ylabel("end-to-end speedup over the CPU solver")
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dest)


def fig_trees(sessions, dest):
    fig, axes = plt.subplots(1, 2, figsize=(8.2, 3.4), sharex=True)
    for ax, field, title in ((axes[0], "wall_s", "end to end (wall clock)"),
                             (axes[1], "metric_value", "step phase")):
        for head, rows in sessions:
            c = card(head)
            cpu = arm_series(rows, r"t2_cpu_n(\d+)$", field)
            for pat, ls, tag in ((r"t2_cuda_n(\d+)$", "-", "CUDA"),
                                 (r"t2_ocl_n(\d+)$", "--", "OpenCL")):
                s = ratio_series(cpu, arm_series(rows, pat, field))
                if s:
                    errplot(ax, s, "%s %s" % (c, tag), CARD_COLOR.get(c, INK), ls=ls)
        ax.set_xscale("log")
        ax.set_yscale("log")
        plain_log(ax)
        ax.set_xlabel("neurons ($\\times$16 compartments)")
        ax.set_title(title, fontsize=9)
    axes[0].set_ylabel("speedup over the CPU solver")
    axes[0].legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dest)


def fig_crossover(sessions, dest):
    cards = sorted({card(h) for h, _ in sessions})
    fig, axes = plt.subplots(1, max(len(cards), 1), figsize=(4.1 * max(len(cards), 1), 3.4),
                             squeeze=False)
    for ax, c in zip(axes[0], cards):
        for head, rows in sessions:
            if card(head) != c:
                continue
            for pat, color, ls, tag in ((r"g32_k(\d+)$", CARD_COLOR.get(c, INK), "-", "GENESIS fp32"),
                                        (r"g64_k(\d+)$", CARD_COLOR.get(c, INK), "--", "GENESIS fp64"),
                                        (r"arb_k(\d+)$", ARBOR_COLOR, "-", "Arbor")):
                s = arm_series(rows, pat)
                if s:
                    errplot(ax, s, tag, color, ls=ls)
        ax.set_xscale("log")
        ax.set_yscale("log")
        plain_log(ax)
        ax.set_xlabel("simulation steps $K$")
        ax.set_title(c, fontsize=9)
        ax.legend(frameon=False, fontsize=8)
    axes[0][0].set_ylabel("wall time (s)")
    fig.tight_layout()
    fig.savefig(dest)


def fig_construction(sessions, before_csv, dest):
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    if os.path.exists(before_csv):
        acc = {}
        with open(before_csv) as f:
            for r in csv.DictReader(f):
                if r["variant"] == "before":
                    acc.setdefault(int(r["ncompts"]), []).append(float(r["total_wallclock_s"]))
        errplot(ax, {k: stats(v) for k, v in sorted(acc.items())},
                "GENESIS 2.4, before the fixes (laptop, August 2026)", "#8a8f98", ls="--", marker="s")
    for head, rows in sessions:
        s = arm_series(rows, r"con_n(\d+)$")
        s17 = {k * 17: v for k, v in s.items()}   # 17 compartments per cell
        errplot(ax, s17, "%s (%s)" % (head.get("describe", "v2.6.0"), head.get("node", "?")),
                CARD_COLOR["A100"])
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("compartments")
    ax.set_ylabel("construction wall time (s)")
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dest)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", default="cluster_bringup/logs/campaign_v2.6.0-rc2")
    ap.add_argument("--out", default="paper/figures")
    ap.add_argument("--before", default="experiments/data/construction_scaling_before_after.csv")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    jobs = (("E2", fig_runlength, "fig_runlength.pdf"),
            ("E3", fig_trees, "fig_trees.pdf"),
            ("E4", fig_crossover, "fig_crossover.pdf"),
            ("E3c", None, "fig_construction.pdf"))
    missing = []
    for exp, fn, name in jobs:
        sessions = read_sessions(a.campaign, exp)
        dest = os.path.join(a.out, name)
        if not sessions:
            missing.append(exp)
            continue
        if exp == "E3c":
            fig_construction(sessions, a.before, dest)
        else:
            fn(sessions, dest)
        print("written: " + dest)
    if missing:
        print("no data yet for: " + ", ".join(missing), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
