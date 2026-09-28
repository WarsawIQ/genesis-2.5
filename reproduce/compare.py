#!/usr/bin/env python3
"""Measured against published, one verdict per claim.

The numbers are the claims, so these are what get checked. Figures follow from
them: the plotting scripts in paper/scripts/ read the same CSVs, so a reviewer
who runs this pack can regenerate the paper's figures from their own hardware.

Published values come from published.csv, which make_numbers.py computes from
the raw data, and tolerances from claims.csv; nothing here is typed by hand.
Tolerances are deliberately loose. GPU clock state,
card model and host CPU all move absolute timings; what should reproduce is the
shape of each result -- which arm wins, and roughly by how much. A run that
lands outside tolerance is worth looking into, not automatically a failure of
the software.
"""

# Deliberately plain Python: no annotations, no f-string niceties beyond 3.6,
# no third-party imports. A reviewer's cluster may ship python3.6, and a
# reproduction pack that needs its own toolchain installed first is not one.
import csv
import sys
import os


def load_measured(path):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                out[row["claim"]] = (float(row["measured"]), row.get("units", ""))
            except (KeyError, ValueError):
                continue
    return out


def load_published(here):
    pub, meta = {}, {}
    with open(os.path.join(here, "published.csv"), newline="") as f:
        for r in csv.DictReader(f):
            pub[r["id"]] = float(r["value"])
    with open(os.path.join(here, "claims.csv"), newline="") as f:
        for r in csv.DictReader(l for l in f if not l.startswith("#")):
            meta[r["id"]] = r
    return pub, meta


def main():
    if len(sys.argv) != 2:
        print("usage: compare.py <summary.csv>", file=sys.stderr)
        return 2
    measured = load_measured(sys.argv[1])
    pub, meta = load_published(os.path.dirname(os.path.abspath(__file__)))

    rows, checked, passed, unknown = [], 0, 0, []
    for claim, (val, _units) in measured.items():
        if claim not in pub:
            unknown.append(claim)
            continue
        exp = pub[claim]
        tol = float(meta[claim]["tolerance_pct"] or 25)
        table = meta[claim]["where"].split(";")[0]
        checked += 1
        # The correctness claim is an order of magnitude, not a value.
        if claim == "cuda_parity_v":
            ok = val <= exp * 10
            delta = f"{val:.1e}"
        else:
            ok = abs(val - exp) <= abs(exp) * tol / 100.0
            delta = f"{(val - exp) / exp * 100:+.0f}%"
        passed += ok
        rows.append((claim, table, f"{exp:.3g}", f"{val:g}", delta,
                     "ok" if ok else "OUTSIDE"))
    missing = len(pub) - checked
    if unknown:
        print("measured but not in the claim map (a stage and claims.csv disagree):")
        for u in unknown:
            print("  " + u)
        print()
    if not rows:
        print("nothing measured -- did a stage fail?")
        return 1

    w = max(len(r[0]) for r in rows) + 2
    print(f"{'claim':<{w}}{'table':<16}{'published':>10}{'measured':>12}{'delta':>9}  verdict")
    print("-" * (w + 55))
    for claim, table, exp, got, delta, verdict in rows:
        print(f"{claim:<{w}}{table:<16}{exp:>10}{got:>12}{delta:>9}  {verdict}")

    print()
    print(f"{passed}/{checked} claims reproduced within tolerance", end="")
    print(f"; {missing} of the paper's {len(pub)} not covered by this run" if missing else "")

    if checked and passed < checked:
        print()
        print("A claim outside tolerance is usually hardware, not a defect:")
        print("  - a GPU shared with another job inflates every GPU figure")
        print("  - a cold card runs 1.2-1.8x slower than a warm one")
        print("  - absolute timings track the host CPU and card model")
        print("Check nvidia-smi and re-run before concluding anything.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
