#!/usr/bin/env python3
"""Are the three implementations of the multi-compartment benchmark the same model?

Table 7 compares GENESIS, NEURON and Arbor on throughput. The equivalence of
the three implementations is argued from matching geometry, conductances,
injection and timestep -- an argument, not a measurement, and the weakest point
in that comparison. This turns it into a measurement.

The model fires repetitively under constant current, so two invariants are used
rather than a point-by-point comparison of the whole run:

  * the first action potential -- peak time and shape, taken before phase drift
    has anything to accumulate over;
  * the firing rate over the full run -- what survives phase drift.

Comparing Vm at the last step would be a test a correct implementation fails,
for the same reason the paper's fp32-vs-fp64 comparison uses a single-AP window.

Two probes per simulator: the soma, which carries the injected current, and the
centre of the last dendrite, which only moves if axial coupling is integrated --
the part hines_tree_eliminate takes over on the GPU.

Usage:  compare_vm_traces.py <dir-of-csvs> [--figure out.png]
"""

import csv
import os
import sys

SPIKE_THRESHOLD_MV = -20.0

# label -> filename, in the order they should be reported
ARMS = [
    ("GENESIS 2.5 CPU", "genesis_cpu.csv"),
    ("GENESIS 2.5 GPU", "genesis_gpu.csv"),
    ("NEURON 9.0.2", "neuron.csv"),
    ("Arbor 0.10.0 CPU", "arbor_cpu.csv"),
    ("Arbor 0.10.0 GPU", "arbor_gpu.csv"),
]

REFERENCE = "NEURON 9.0.2"


def load(path):
    t, soma, far = [], [], []
    with open(path) as fh:
        for row in csv.DictReader(fh):
            try:
                t.append(float(row["t_ms"]))
                soma.append(float(row["vm_soma_mV"]))
                far.append(float(row["vm_far_mV"]))
            except (ValueError, KeyError):
                continue
    return t, soma, far


def spike_times(t, v, thresh=SPIKE_THRESHOLD_MV):
    """Upward threshold crossings, then the local maximum after each."""
    out = []
    for i in range(1, len(v)):
        if v[i - 1] < thresh <= v[i]:
            j = i
            while j + 1 < len(v) and v[j + 1] >= v[j]:
                j += 1
            out.append((t[j], v[j]))
    return out


def resample(t_src, v_src, t_dst):
    """Linear interpolation of (t_src, v_src) onto t_dst."""
    out = []
    i = 0
    for t in t_dst:
        while i + 1 < len(t_src) and t_src[i + 1] < t:
            i += 1
        if i + 1 >= len(t_src):
            out.append(v_src[-1])
        elif t_src[i + 1] == t_src[i]:
            out.append(v_src[i])
        else:
            w = (t - t_src[i]) / (t_src[i + 1] - t_src[i])
            out.append(v_src[i] + w * (v_src[i + 1] - v_src[i]))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: compare_vm_traces.py <dir-of-csvs> [--figure out.png]")
    d = sys.argv[1]
    figure = None
    if "--figure" in sys.argv:
        figure = sys.argv[sys.argv.index("--figure") + 1]

    traces = {}
    for label, fname in ARMS:
        p = os.path.join(d, fname)
        if not os.path.exists(p):
            print("missing (skipped): %s" % fname)
            continue
        t, soma, far = load(p)
        if len(t) < 10:
            print("too short (skipped): %s -- %d rows" % (fname, len(t)))
            continue
        traces[label] = (t, soma, far)

    if REFERENCE not in traces:
        sys.exit("no reference arm (%s); cannot compare" % REFERENCE)

    print("=" * 78)
    print("Multi-compartment HH benchmark, one cell, Vm at the soma and at the")
    print("centre of the last dendrite. Reference arm: %s." % REFERENCE)
    print("=" * 78)
    print()

    # ---- per-arm summary -------------------------------------------------
    print("%-18s %8s %9s %9s %9s %9s" % (
        "arm", "samples", "duration", "spikes", "rate Hz", "AP1 ms"))
    summary = {}
    for label, (t, soma, far) in traces.items():
        sp = spike_times(t, soma)
        dur_s = (t[-1] - t[0]) / 1000.0
        rate = len(sp) / dur_s if dur_s > 0 else float("nan")
        ap1 = sp[0][0] if sp else float("nan")
        summary[label] = dict(spikes=len(sp), rate=rate, ap1=ap1, first=sp[0] if sp else None)
        print("%-18s %8d %8.1fms %9d %9.2f %9.3f" % (
            label, len(t), t[-1] - t[0], len(sp), rate, ap1))
    print()

    # ---- first action potential ------------------------------------------
    ref_t, ref_soma, ref_far = traces[REFERENCE]
    ref_sp = summary[REFERENCE]["first"]
    if ref_sp is None:
        print("reference arm never crossed threshold; nothing to align on")
        return
    t0, t1 = max(0.0, ref_sp[0] - 3.0), ref_sp[0] + 3.0
    win = [t for t in ref_t if t0 <= t <= t1]
    print("First action potential, window %.2f-%.2f ms around the reference peak." % (t0, t1))
    print("Differences are against %s, on the same time grid." % REFERENCE)
    print()
    print("%-18s %12s %12s %12s %12s %10s" % (
        "arm", "peak mV", "d peak mV", "max|d| soma", "max|d| far", "shift ms"))
    # Shape is compared after shifting each arm so its first peak sits on the
    # reference's. Without that the numbers report how far apart the spikes are
    # in time, not how differently they are shaped: on a 100 V/s upstroke a
    # 0.1 ms offset alone is 10 mV.
    ref_s_win = resample(ref_t, ref_soma, win)
    ref_f_win = resample(ref_t, ref_far, win)
    for label, (t, soma, far) in traces.items():
        pk = summary[label]["first"]
        pk_v = pk[1] if pk else float("nan")
        shift = (pk[0] - ref_sp[0]) if pk else 0.0
        s_win = resample(t, soma, [x + shift for x in win])
        f_win = resample(t, far, [x + shift for x in win])
        ds = max(abs(a - b) for a, b in zip(s_win, ref_s_win))
        df = max(abs(a - b) for a, b in zip(f_win, ref_f_win))
        print("%-18s %12.4f %12.4f %12.5f %12.5f %10.4f" % (
            label, pk_v, pk_v - ref_sp[1], ds, df, shift))
    print()

    # ---- rate agreement ---------------------------------------------------
    ref_rate = summary[REFERENCE]["rate"]
    print("Firing rate over the full run, against %s (%.2f Hz):" % (REFERENCE, ref_rate))
    for label in traces:
        r = summary[label]["rate"]
        rel = 100.0 * (r - ref_rate) / ref_rate if ref_rate else float("nan")
        print("  %-18s %7.2f Hz   %+6.2f %%" % (label, r, rel))
    print()

    if figure:
        make_figure(traces, win, figure)


def make_figure(traces, win, out):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib unavailable; no figure written")
        return

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, axes = plt.subplots(1, 2, figsize=(10.0, 3.8))
    # NEURON is drawn wide and pale underneath so that Arbor lying exactly on
    # top of it reads as agreement rather than as a missing line; the same
    # device separates the GENESIS CPU and GPU arms, which also coincide.
    styles = {
        "NEURON 9.0.2": dict(color="#c3c7cc", lw=5.0, zorder=1,
                             solid_capstyle="round"),
        "Arbor 0.10.0 CPU": dict(color="#b3541e", lw=1.6, zorder=3),
        "Arbor 0.10.0 GPU": dict(color="#f0a875", lw=1.6, ls=(0, (3, 2)), zorder=4),
        "GENESIS 2.5 CPU": dict(color="#7fc3a1", lw=5.0, zorder=2,
                                solid_capstyle="round"),
        "GENESIS 2.5 GPU": dict(color="#0f5c37", lw=1.6, ls=(0, (3, 2)), zorder=5),
    }
    order = ["GENESIS 2.5 CPU", "GENESIS 2.5 GPU", "NEURON 9.0.2",
             "Arbor 0.10.0 CPU", "Arbor 0.10.0 GPU"]
    for ax, idx, title in ((axes[0], 1, "soma (injection site)"),
                           (axes[1], 2, "last dendrite (axial coupling)")):
        for label in order:
            if label not in traces:
                continue
            tr = traces[label]
            t, v = tr[0], tr[idx]
            vv = resample(t, v, win)
            ax.plot(win, vv, label=label, **styles.get(label, {}))
        ax.set_title(title, fontsize=10)
        ax.set_xlabel("time (ms)")
        ax.set_ylim(-90, 62)
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
    axes[0].set_ylabel("membrane potential (mV)")
    axes[0].legend(fontsize=7.5, frameon=False, loc="upper left",
                   handlelength=2.6, borderaxespad=0.2)
    fig.tight_layout()
    fig.savefig(out, dpi=320, bbox_inches="tight")
    plt.close(fig)
    print("Wrote:", out)


if __name__ == "__main__":
    main()
