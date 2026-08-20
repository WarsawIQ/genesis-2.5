#!/usr/bin/env python3
"""Figure: where GENESIS 2.5 sits against NEURON, CoreNEURON and Arbor.

The figure answers one question -- who runs the Vogels-Abbott network fastest --
so the title states the answer and the chart is stripped to what supports it.
One number per bar (wall clock; throughput is that number divided into a
constant, so printing both said the same thing twice). Single-line labels with
the device as a suffix, because two-line labels made the left edge the busiest
part of the plot. A dashed guide at the GENESIS time lets every slower bar be
read against it without a second annotation.

Colour carries the only distinction that matters: GENESIS, the arms on a GPU,
and the rest on CPU.

Data: cluster_bringup/coreneuron/README.md, UMCS node inf03, 4000 cells, 5.0 s
simulated, dt = 0.05 ms.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt

ACCENT = "#1e7f4f"   # GENESIS -- same green as the A100 series in fig10
NEUTRAL = "#8a8f98"  # the simulators being compared against, on CPU
GPU = "#b3541e"      # the arms that run on an accelerator
INK = "#222222"
MUTED = "#5a5f66"

# label, mean seconds, std (None = single run)
ROWS = [
    ("CoreNEURON 9.0.2 · GPU", 27.0, 0.1),
    ("GENESIS 2.5, one solver per layer", 33.2, 0.7),
    ("GENESIS 2.5, as published", 46.9, 2.1),
    ("CoreNEURON 9.0.2", 76.5, 0.3),
    ("NEURON 9.0.2", 95.8, 0.2),
    ("NEURON 9.0.2, ChannelBuilder", 123.3, None),
    ("Arbor 0.10.0 · GPU", 149.4, 1.1),
]

GENESIS_S = 33.2
CORENEURON_CPU_S = 76.5


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    figures = root / "figures"
    figures.mkdir(exist_ok=True)

    rows = sorted(ROWS, key=lambda r: r[1])
    labels = [r[0] for r in rows]
    means = [r[1] for r in rows]
    errs = [r[2] if r[2] is not None else 0.0 for r in rows]

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, ax = plt.subplots(figsize=(8.0, 3.6))

    y = list(range(len(rows)))
    colors = [ACCENT if "GENESIS" in l else GPU if "GPU" in l else NEUTRAL
              for l in labels]
    ax.barh(y, means, xerr=errs, height=0.6, color=colors,
            error_kw={"ecolor": "#444444", "capsize": 2.5, "lw": 1.0},
            zorder=3)

    # Read every slower arm against the GENESIS time without a second annotation.
    ax.axvline(GENESIS_S, color=ACCENT, lw=1.0, ls=(0, (4, 3)), alpha=0.55,
               zorder=2)

    for i, (_l, m, e) in enumerate(rows):
        note = f"{m:.1f} s" if e is not None else f"{m:.1f} s (single run)"
        ax.text(m + (e or 0) + 2.5, i, note, va="center", ha="left",
                fontsize=9.5, color=INK)

    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=9.5)
    ax.invert_yaxis()
    ax.set_xlabel("Wall-clock time for the 5 s simulation (s), lower is better")
    ax.set_xlim(0, 185)
    ax.grid(True, axis="x", alpha=0.3)
    ax.grid(False, axis="y")
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.tick_params(axis="y", length=0)

    ratio = CORENEURON_CPU_S / GENESIS_S
    ax.set_title(
        f"On one CPU core, GENESIS 2.5 runs this network {ratio:.1f}× faster "
        "than CoreNEURON",
        fontsize=11.5, loc="left", color=INK, pad=26)
    ax.text(0.0, 1.02,
            "Only CoreNEURON on a GPU is faster — Vogels–Abbott COBAHH, "
            "4000 cells, 5 s at dt = 0.05 ms, one node",
            transform=ax.transAxes, fontsize=9, color=MUTED, va="bottom")

    fig.tight_layout()
    out = figures / "fig12_coreneuron_comparison.png"
    fig.savefig(out, dpi=320, bbox_inches="tight")
    plt.close(fig)
    print("Wrote:", out)


if __name__ == "__main__":
    main()
