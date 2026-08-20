#!/usr/bin/env python3
"""Where GENESIS 2.5 overtakes Arbor, and how that point moves with the card.

Both simulators are linear in the number of steps, with different intercepts and
slopes: Arbor starts ahead on setup, GENESIS advances each step more cheaply.
The lines therefore cross, and the crossing is the result -- neither simulator
is faster in general, and a single-run-length comparison would report whichever
side of it the author happened to pick.

One panel per card, because the crossing is not a property of the two
simulators alone: our kernel is fp32 where Arbor computes in double, so the A40
-- whose double-precision throughput is a fraction of the A100's -- moves the
crossing much earlier.

Only the GPU arms are plotted; the CPU arms belong to a different comparison and
are two orders of magnitude away.
"""

from __future__ import annotations

import csv
import statistics
from pathlib import Path

import matplotlib.pyplot as plt

GENESIS_COLOR = "#1e7f4f"
ARBOR_COLOR = "#9c5315"
INK = "#222222"
MUTED = "#5a5f66"

# One sweep per card, each a single session with one model version. Pooling
# files taken on different days would mix model versions; the fits are only
# reproducible from a named dataset.
SWEEPS = [
    ("NVIDIA A100", "crossover_inf03_20260818_232057.csv"),
    ("NVIDIA A40", "crossover_inf02_20260820_131248.csv"),
]


def load(path: Path) -> dict[str, dict[int, list[float]]]:
    """GPU wall times by simulator and step count, from one sweep."""
    out: dict[str, dict[int, list[float]]] = {}
    with path.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            backend = (r.get("backend") or "GPU").upper()
            if "GPU" not in backend:
                continue
            try:
                k, w = int(r["n_steps"]), float(r["wall_s"])
            except (KeyError, ValueError):
                continue
            out.setdefault(r["simulator"], {}).setdefault(k, []).append(w)
    return out


def fit(ks: list[int], ts: list[float]) -> tuple[float, float]:
    """Least-squares intercept and per-step slope."""
    n = len(ks)
    mx, my = sum(ks) / n, sum(ts) / n
    sxx = sum((k - mx) ** 2 for k in ks)
    sxy = sum((k - mx) * (t - my) for k, t in zip(ks, ts))
    slope = sxy / sxx if sxx else 0.0
    return my - slope * mx, slope


def panel(ax, data, card: str) -> float:
    series = {}
    for name, color in (("GENESIS 2.5", GENESIS_COLOR),
                        ("Arbor 0.10.0", ARBOR_COLOR)):
        by_k = data.get(name)
        if not by_k:
            raise SystemExit(f"{card}: missing {name}")
        ks = sorted(by_k)
        means = [statistics.mean(by_k[k]) for k in ks]
        sds = [statistics.stdev(by_k[k]) if len(by_k[k]) > 1 else 0.0 for k in ks]
        series[name] = (ks, means, sds, color, fit(ks, means))

    kmax = max(max(s[0]) for s in series.values()) * 1.05
    for name, (ks, means, sds, color, (c0, c1)) in series.items():
        ax.errorbar(ks, means, yerr=sds, color=color, marker="o", markersize=6,
                    linestyle="none", capsize=3, zorder=3,
                    label=f"{name}: {c0:.2f} s + {c1 * 1e6:.0f} $\\mu$s/step")
        ax.plot([0, kmax], [c0, c0 + c1 * kmax], color=color, linewidth=1.6,
                linestyle="--", alpha=0.85, zorder=2)

    (_, _, _, _, (g0, g1)) = series["GENESIS 2.5"]
    (_, _, _, _, (a0, a1)) = series["Arbor 0.10.0"]
    cross = (a0 - g0) / (g1 - a1)
    ycross = g0 + g1 * cross
    ax.axvline(cross, color="#444444", linewidth=1.0, linestyle=":", zorder=1)
    ax.plot([cross], [ycross], marker="D", color=INK, markersize=6, zorder=4)
    ax.set_title(f"{card} — GENESIS ahead from K $\\approx$ {cross:,.0f}"
                 f"  ({cross * 0.01:.0f} ms simulated)",
                 fontsize=10, loc="left", color=MUTED, pad=6)
    ax.set_xlabel("K, simulation steps (dt = 0.01 ms)")
    ax.set_xlim(0, kmax)
    ax.set_ylim(0, None)
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper left", fontsize=8)
    return cross


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    logs = root.parent / "cluster_bringup" / "logs"
    figures = root / "figures"
    figures.mkdir(exist_ok=True)

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, axes = plt.subplots(1, 2, figsize=(10.0, 4.2))

    crossings = []
    for ax, (card, sweep) in zip(axes, SWEEPS):
        crossings.append((card, panel(ax, load(logs / sweep), card)))
    axes[0].set_ylabel("Wall-clock time (s), lower is better")

    fig.tight_layout(rect=(0, 0, 1, 0.88))
    fig.text(0.005, 0.965,
             "Which simulator is faster depends on run length — and on the card",
             fontsize=12, color=INK, ha="left", va="bottom")
    fig.text(0.005, 0.905,
             "GENESIS 2.5 advances each step more cheaply than Arbor on both "
             "cards, so it wins every run longer than the marked point; "
             "10,000 neurons × 16 compartments",
             fontsize=9, color=MUTED, ha="left", va="bottom")
    out = figures / "fig13_crossover.png"
    fig.savefig(out, dpi=320, bbox_inches="tight")
    plt.close(fig)
    print("Wrote:", out)
    for card, k in crossings:
        print(f"  {card}: crossover K = {k:.0f} ({k * 0.01:.1f} ms simulated)")


if __name__ == "__main__":
    main()
