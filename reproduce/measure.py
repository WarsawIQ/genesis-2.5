#!/usr/bin/env python3
"""The revised paper's numbers, measured from a reader's run.

    python3 reproduce/measure.py <results dir>          the verdict table
    python3 reproduce/measure.py --per-claim <dir>      one line per claim
    python3 reproduce/measure.py --stage-ours <dir>     lay our own data out as a reader's run
    python3 reproduce/measure.py --self-test            stage ours, measure, expect every
                                                        published value back

reproduce/run_all.sh runs the campaign stages (cluster_bringup/campaign/) in the
reader's mode and leaves their files under <results dir>: campaign/E*_tidy.csv,
campaign/E5_*_spikes.csv, chanmode/data.csv and ap_check.txt. Every number the
revised manuscript prints is a row of reproduce/claims.csv that names its data
file and its extractor. This swaps the data file for the reader's file of the
same experiment and runs the same extractor on it, so the reader's number is
computed exactly as ours was; derived numbers are recomputed from the reader's
inputs with the same formula.

Verdicts. A number that does not depend on the card (a construction exponent,
a ratio of two CPU modes, the CPU's membrane potential) is checked against its
tolerance in claims.csv. An absolute time (seconds on our machine) is printed
for information only: it depends on the machine. A ratio whose notes in
claims.csv say "shape only" (the CPU solver's modes, whose ratio depends on the
processor) is checked by its shape, like a GPU number on another card; a ratio
within its own tolerance of 1 has no side and is printed for information. A number measured on an A40 or an A100 is checked the
same way when the reader's card is that card; on another card only its shape
is checked: a speedup must stay on the same side of 1. Uncertainties (_sd) are
printed with nothing to check.

Plain Python 3.6, standard library only, like the rest of reproduce/.
"""

import csv
import glob
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import claims_extract                      # noqa: E402
from make_numbers import fmt               # noqa: E402

MANUSCRIPT = os.path.join(ROOT, "paper", "manuscript_softwarex_revision.tex")

# the where-tags of claims.csv as the revised manuscript numbers them
WHERE = {"abstract": "abstract", "sec:2": "Section 2", "sec:3": "Section 3",
         "sec:4": "Section 4", "sec:5": "Section 5", "tab:single": "Table 2",
         "tab:sim": "Table 3", "tab:regimes": "Table 4", "fig:trees": "Fig. 2",
         "fig:runlength": "Fig. 3", "fig:crossover": "Fig. 4",
         "fig:construction": "Fig. 5"}

# (pattern on a claim's data path, where a reader's run leaves the same kind of file)
SOURCES = [
    (r"/(E\d+c?)_[^/]*_tidy\.csv$", "campaign/{0}_*_tidy.csv"),
    (r"/(E5)_[^/]*_spikes\.csv$", "campaign/{0}_*_spikes.csv"),
    (r"/(chanmode)_check_[^/]*/data\.csv$", "chanmode/data.csv"),
    (r"(accel_regression)_golden\.txt$", "ap_check.txt"),
]

# what a reader needs for the numbers a run did not measure, by experiment
GPU = "a GPU run (run_all.sh --quick; the full sizes without --quick)"
NEEDS = {"E2": GPU, "E3": GPU, "E8": GPU, "E5": "a full GPU run (run_all.sh)",
         "E7": "a full GPU run (run_all.sh)",
         "E3c": "the full sizes (run_all.sh --cpu-only, without --quick)",
         "chanmode": "run_all.sh --cpu-only", "accel_regression": "run_all.sh --cpu-only",
         "E1": "run_all.sh --with-simulators (NEURON, CoreNEURON, Arbor)",
         "E4": "run_all.sh --with-simulators (Arbor)"}
ELSEWHERE = [
    (r"/E6_", "perf profiles: cluster_bringup/campaign/E6_profile.sh"),
    (r"/E9_|e9_rusticl|/runs/victor_", "an AMD Radeon 890M: cluster_bringup/campaign/E9_890m.sh"),
    (r"numa_check", "the cluster's two sockets: cluster_bringup/campaign/numa_check.sh"),
    (r"host_kernel", "Nsight Systems: cluster_bringup/campaign/host_kernel_profile.sh"),
    (r"construction_before", "the code before the fixes: cluster_bringup/campaign/construction_before.sh"),
    (r"^genesis/", "nothing: read from the source code"),
]
CARD = {"a40": "A40", "a100": "A100"}
# a mean or sd of these columns is a time on the machine that ran it: printed,
# never judged (a ratio of two of them is judged)
WALL = ("wall_s", "total_wallclock_s", "t_per_step_s")
SAFE = {"__builtins__": {}, "abs": abs, "min": min, "max": max}


def load_claims():
    with open(os.path.join(HERE, "claims.csv"), newline="") as f:
        return {r["id"]: r for r in csv.DictReader(l for l in f if not l.startswith("#"))}


def load_published():
    with open(os.path.join(HERE, "published.csv"), newline="") as f:
        return {r["id"]: float(r["value"]) for r in csv.DictReader(f)}


def paper_claims(claims):
    """Ids the manuscript prints, and every input they are computed from."""
    text = "\n".join(re.sub(r"(?<!\\)%.*$", "", l) for l in open(MANUSCRIPT).read().split("\n"))
    used = set(re.findall(r"\\claim\{([^}]+)\}", text))
    closure, todo = set(), list(used)
    while todo:
        c = todo.pop()
        if c in closure:
            continue
        closure.add(c)
        todo.extend(i for i in claims[c]["inputs"].split(";") if i)
    return used, closure


def source_of(data):
    """(pattern index, experiment key) of a claim's data path, or (None, None)."""
    for i, (pat, _) in enumerate(SOURCES):
        m = re.search(pat, data)
        if m:
            return i, m.group(1)
    return None, None


def gpu_of(path):
    """The '# gpu:' header of the session a reader's (or our) file comes from."""
    raw = re.sub(r"_(tidy|spikes)\.csv$", ".csv", path)
    for p in (raw, path):
        try:
            with open(p, errors="replace") as f:
                for line in f:
                    if not line.startswith("#"):
                        break
                    m = re.match(r"#\s*gpu:\s*(.*)", line)
                    if m:
                        return m.group(1).strip()
        except OSError:
            pass
    return ""


def on_card(path, card):
    return bool(re.search(r"\b%s\b" % card, gpu_of(path)))


def locate(results, claim):
    """The reader's file for this claim's data, preferring the claim's own card."""
    data = claim["data"]
    i, key = source_of(data)
    if i is None:
        return None
    hits = glob.glob(os.path.join(results, SOURCES[i][1].format(key)))
    if not hits:
        return None
    card = CARD.get(claim["hardware"])
    same = [h for h in hits if card and on_card(h, card)]
    return sorted(same or hits, key=os.path.getmtime)[-1]


def evaluate(results, claims, ids):
    vals, files = {}, {}

    def value(cid):
        if cid in vals:
            return vals[cid]
        c = claims[cid]
        v = None
        if c["kind"] == "measured":
            path = locate(results, c)
            if path:
                row = dict(c)
                row["data"] = path
                try:
                    v = claims_extract.extract(row)
                    files[cid] = path
                except Exception:            # too few points, a missing arm: not measured
                    v = None
        elif c["kind"] == "derived":
            inputs = [i for i in c["inputs"].split(";") if i]
            env = {}
            for i in inputs:
                x = value(i)
                if x is None:
                    break
                env[i] = x
            else:
                try:
                    v = float(eval(c["extract"], SAFE, env))
                except Exception:
                    v = None
                got = [files[i] for i in inputs if i in files]
                if got:
                    files[cid] = got[0]
        vals[cid] = v
        return v

    for cid in sorted(ids):
        value(cid)
    return vals, files


def shape(claim, pubs, val):
    """Same side of 1 as every published value. A ratio within the claim's own
    tolerance of 1 has no side here (two arms within the noise): information."""
    tol = float(claim["tolerance_pct"] or 25) / 100.0
    if abs(val - 1.0) <= tol or any(p == 1.0 for p in pubs):
        return "info"
    return "same shape" if all((val - 1.0) * (p - 1.0) > 0 for p in pubs) else "DIFFERENT SHAPE"


def within(claim, pub, val):
    tol = float(claim["tolerance_pct"] or 25)
    return abs(val - pub) <= abs(pub) * tol / 100.0


def why_missing(claims, cid, vals):
    """What a reader needs for this number; a derived one needs its first missing input."""
    claim = claims[cid]
    if claim["kind"] == "derived":
        for i in claim["inputs"].split(";"):
            if i and vals.get(i) is None:
                return why_missing(claims, i, vals)
    for pat, why in ELSEWHERE:
        if re.search(pat, claim["data"]):
            return why
    i, key = source_of(claim["data"])
    if key == "accel_regression" and claim["hardware"] in CARD:
        return GPU                           # the GPU's value of the action potential check
    if key in NEEDS:
        return NEEDS[key]
    if claim["kind"] == "cited":
        return "nothing: cited from the literature"
    return "no raw data"


def where(claim):
    return ", ".join(WHERE.get(w, w) for w in claim["where"].split(";") if w) or "-"


def table(results):
    claims, pub = load_claims(), load_published()
    used, closure = paper_claims(claims)
    vals, files = evaluate(results, claims, closure)

    groups = {}
    for cid in sorted(used):
        if cid.endswith("_sd"):
            continue
        base = re.sub(r"_a(40|100)(?=_|$)", "", cid)
        groups.setdefault(base, []).append(cid)

    rows, missing = [], {}
    counts = {"ok": 0, "OUTSIDE": 0, "same shape": 0, "DIFFERENT SHAPE": 0, "info": 0}
    for base, ids in sorted(groups.items()):
        got = [c for c in ids if vals.get(c) is not None]
        if not got:
            why = why_missing(claims, ids[0], vals)
            missing[why] = missing.get(why, 0) + 1
            continue
        c0 = claims[got[0]]
        v = vals[got[0]]
        cards = [c for c in ids if claims[c]["hardware"] in CARD]
        timed = c0["kind"] == "measured" and c0["extract"] in ("mean", "sd") and c0["col"] in WALL
        shape_only = c0["notes"].startswith("shape only")
        if shape_only and got[0] in pub:
            published = fmt(pub[got[0]], c0["format"])
            verdict = shape(c0, [pub[got[0]]], v)
            card_note = ""
        elif timed:
            published = " / ".join(("%s " % CARD[claims[c]["hardware"]] if claims[c]["hardware"] in CARD else "")
                                   + fmt(pub[c], claims[c]["format"]) for c in ids if c in pub)
            verdict = "info"
            card_note = gpu_of(files.get(got[0], "")) if cards else ""
        elif cards:
            path = files.get(got[0], "")
            mine = [c for c in cards if on_card(path, CARD[claims[c]["hardware"]])]
            published = " / ".join("%s %s" % (CARD[claims[c]["hardware"]], fmt(pub[c], claims[c]["format"]))
                                   for c in cards if c in pub)
            if mine:
                c = mine[0]
                v = vals[c]
                verdict = "ok" if within(claims[c], pub[c], v) else "OUTSIDE"
            elif c0["units"] == "x" and all(c in pub for c in cards):
                verdict = shape(c0, [pub[c] for c in cards], v)
            else:
                verdict = "info"
            card_note = gpu_of(path) or "unknown card"
        else:
            published = fmt(pub[got[0]], c0["format"]) if got[0] in pub else "-"
            verdict = "ok" if got[0] in pub and within(c0, pub[got[0]], v) else (
                "OUTSIDE" if got[0] in pub else "info")
            card_note = ""
        counts[verdict] += 1
        rows.append((base, where(c0), published, fmt(v, c0["format"]), verdict, card_note))
    return rows, counts, missing


def print_table(results):
    rows, counts, missing = table(results)
    if not rows:
        print("nothing measured -- did a stage fail? (results: %s)" % results)
        return 1
    w = max(len(r[0]) for r in rows) + 2
    wp = max(len(r[2]) for r in rows) + 2
    print("%-*s%-22s%-*s%12s  %s" % (w, "number", "in the paper", wp, "published", "yours", "verdict"))
    print("-" * (w + wp + 50))
    for base, wh, published, yours, verdict, card in rows:
        print("%-*s%-22s%-*s%12s  %s" % (w, base, wh[:21], wp, published, yours, verdict))
    cards = sorted({r[5] for r in rows if r[5]})
    print()
    print("%d numbers measured: %d ok, %d outside tolerance; by shape (another card, or a ratio "
          "that depends on the CPU) %d same, %d different; %d for information (absolute times)"
          % (len(rows), counts["ok"], counts["OUTSIDE"], counts["same shape"],
             counts["DIFFERENT SHAPE"], counts["info"]))
    if cards:
        print("card: %s (the paper's GPU numbers are from an NVIDIA A40 and an A100)" % ", ".join(cards))
    if missing:
        print()
        print("not measured by this run, and what they need:")
        for why, n in sorted(missing.items(), key=lambda x: -x[1]):
            print("  %3d  %s" % (n, why))
    if counts["OUTSIDE"] or counts["DIFFERENT SHAPE"]:
        print()
        print("A number outside tolerance is usually the machine, not the software:")
        print("  - a GPU shared with another job inflates every GPU time")
        print("  - a cold card runs 1.2-1.8x slower than a warm one")
        print("  - absolute times follow the host CPU and the card model")
        print("Check nvidia-smi and the load, and run again before concluding anything.")
    return 0


def per_claim(results):
    claims, pub = load_claims(), load_published()
    used, closure = paper_claims(claims)
    vals, _ = evaluate(results, claims, closure)
    n = 0
    for cid in sorted(closure):
        if vals.get(cid) is None or cid not in pub:
            continue
        n += 1
        print("%s\t%r\t%r\t%s" % (cid, pub[cid], vals[cid],
                                  "ok" if within(claims[cid], pub[cid], vals[cid]) else "OUTSIDE"))
    return 0 if n else 1


def stage_ours(dest):
    """Copy the data behind the paper's numbers into a reader's layout."""
    claims = load_claims()
    _, closure = paper_claims(claims)
    os.makedirs(os.path.join(dest, "campaign"), exist_ok=True)
    os.makedirs(os.path.join(dest, "chanmode"), exist_ok=True)
    n = 0
    for cid in sorted(closure):
        c = claims[cid]
        if c["kind"] != "measured":
            continue
        i, key = source_of(c["data"])
        if i is None:
            continue
        src = os.path.join(ROOT, c["data"])
        if SOURCES[i][1].startswith("campaign/"):
            for p in {src, re.sub(r"_(tidy|spikes)\.csv$", ".csv", src)}:
                if os.path.exists(p):
                    shutil.copy2(p, os.path.join(dest, "campaign", os.path.basename(p)))
        else:
            shutil.copy2(src, os.path.join(dest, SOURCES[i][1]))
        n += 1
    return n


def self_test():
    claims, pub = load_claims(), load_published()
    _, closure = paper_claims(claims)
    tmp = tempfile.mkdtemp(prefix="measure_self_test.")
    try:
        stage_ours(tmp)
        vals, _ = evaluate(tmp, claims, closure)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    checked, bad = 0, []
    for cid in sorted(closure):
        if vals.get(cid) is None or cid not in pub:
            continue
        checked += 1
        p, v = pub[cid], vals[cid]
        if abs(v - p) > 1e-8 * max(1.0, abs(p)):
            bad.append((cid, p, v))
    for cid, p, v in bad:
        print("MISMATCH %s: published %r, from our data %r" % (cid, p, v))
    if not checked:
        print("self-test: nothing measured from our own data")
        return 1
    print("self-test: %d numbers measured from our own data, %s"
          % (checked, "all equal to the published values" if not bad else "%d differ" % len(bad)))
    return 1 if bad else 0


def main(argv):
    if argv[:1] == ["--self-test"]:
        return self_test()
    if argv[:1] == ["--stage-ours"] and len(argv) == 2:
        print("staged %d data files in %s" % (stage_ours(argv[1]), argv[1]))
        return 0
    if argv[:1] == ["--per-claim"] and len(argv) == 2:
        return per_claim(argv[1])
    if len(argv) == 1 and not argv[0].startswith("-"):
        return print_table(argv[0])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
