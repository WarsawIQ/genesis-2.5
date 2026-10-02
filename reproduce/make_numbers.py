#!/usr/bin/env python3
"""Generate every published number from the claim map and the raw data.

    python3 reproduce/make_numbers.py            write the outputs
    python3 reproduce/make_numbers.py --check    change nothing; exit 1 if any
                                                 output would change
    python3 reproduce/make_numbers.py --strict   also fail on claims that have
                                                 no raw data yet (kind "prose")
                                                 or that combine sessions

Reads reproduce/claims.csv and the data files it names. Writes
reproduce/published.csv (read by compare.py), paper/numbers.tex (read by the
manuscript through \\claim{id}), the table between the claims-table markers
in README.md and every <!--claim:id--> number in README.md.

Validation stops at the first broken rule and writes nothing, so a missing,
superseded or mistyped input can never leave a stale number behind.

Plain Python 3.6, standard library only.
"""

import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import claims_extract  # noqa: E402

CLAIMS = os.path.join(HERE, "claims.csv")
PUBLISHED = os.path.join(HERE, "published.csv")
NUMBERS = os.path.join(ROOT, "paper", "numbers.tex")
README = os.path.join(ROOT, "README.md")
SUPERSEDED = os.path.join(ROOT, "cluster_bringup", "logs", "SUPERSEDED.md")
TABLE_BEGIN = "<!-- claims-table:begin -->"
TABLE_END = "<!-- claims-table:end -->"
# A number in README.md written as <!--claim:id-->21.0<!--/claim--> is rewritten
# from the claim map on every run, like \claim{id} in the manuscript.
INLINE_RE = re.compile(r"<!--claim:([^>]*)-->(.*?)<!--/claim-->")

KINDS = {"measured", "derived", "cited", "prose"}
HARDWARE = {"none", "nvidia", "a40", "a100", "a40+a100", "coreneuron-gpu",
            "arbor-gpu", "amd-890m", "cluster-mpi"}
HARDWARE_TEXT = {
    "none": "any Linux machine",
    "nvidia": "any NVIDIA GPU, CUDA 12",
    "a40": "NVIDIA A40",
    "a100": "NVIDIA A100",
    "a40+a100": "NVIDIA A40 and A100",
    "coreneuron-gpu": "NVIDIA GPU with the NVHPC CoreNEURON build",
    "arbor-gpu": "NVIDIA GPU with Arbor built for CUDA",
    "amd-890m": "AMD Radeon 890M (OpenCL)",
    "cluster-mpi": "MPI cluster, up to 24 ranks",
}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class ClaimError(Exception):
    pass


def superseded_paths():
    out = set()
    if not os.path.exists(SUPERSEDED):
        return out
    with open(SUPERSEDED) as f:
        for line in f:
            m = re.match(r"^\|\s*`?([^`|]+?)`?\s*\|", line)
            if m and "/" in m.group(1):
                out.add(m.group(1).strip())
    return out


def load_claims():
    with open(CLAIMS, newline="") as f:
        return [r for r in csv.DictReader(l for l in f if not l.startswith("#"))]


def fmt(value, spec):
    if spec == ",":                       # thousands, LaTeX thin space
        return "{:,}".format(int(round(value))).replace(",", "\\,")
    if spec.endswith("d"):
        return spec % int(round(value))
    return spec % value


def evaluate(claims, strict):
    by_id = {}
    for c in claims:
        cid = c["id"]
        if not ID_RE.match(cid):
            raise ClaimError("%s: ids are lower-case letters, digits and _" % cid)
        if cid in by_id:
            raise ClaimError("%s: duplicate id" % cid)
        if c["kind"] not in KINDS:
            raise ClaimError("%s: unknown kind %r" % (cid, c["kind"]))
        if c["hardware"] not in HARDWARE:
            raise ClaimError("%s: unknown hardware %r" % (cid, c["hardware"]))
        by_id[cid] = c

    stale = superseded_paths()
    values = {}

    def value_of(cid, stack=()):
        if cid in values:
            return values[cid]
        if cid in stack:
            raise ClaimError("cycle through %s" % " -> ".join(stack + (cid,)))
        if cid not in by_id:
            raise ClaimError("%s: unknown input" % cid)
        c = by_id[cid]
        kind = c["kind"]
        if kind == "measured":
            for p in c["data"].split(";"):
                if not os.path.exists(os.path.join(ROOT, p)):
                    raise ClaimError("%s: data file %s does not exist" % (cid, p))
                if p in stale:
                    raise ClaimError("%s: data file %s is marked superseded" % (cid, p))
                if "/campaign_dry/" in "/" + p:
                    raise ClaimError("%s: data file %s is from a campaign dry run, "
                                     "which tests the harness and is not a result" % (cid, p))
            if not c["stage"] or not c["session"]:
                raise ClaimError("%s: measured claims need a stage and a session" % cid)
            row = dict(c)
            row["data"] = os.path.join(ROOT, c["data"])
            try:
                v = claims_extract.extract(row)
            except (claims_extract.ExtractError, ValueError, OSError) as e:
                raise ClaimError("%s: %s" % (cid, e))
        elif kind == "derived":
            inputs = [i for i in c["inputs"].split(";") if i]
            if not inputs:
                raise ClaimError("%s: derived claims need inputs" % cid)
            env = {i: value_of(i, stack + (cid,)) for i in inputs}
            sessions = {by_id[i]["session"] for i in inputs if by_id[i]["session"]}
            if len(sessions) > 1 and "cross-session-ok" not in c["notes"]:
                raise ClaimError("%s: inputs come from different sessions %s"
                                 % (cid, sorted(sessions)))
            if strict and len(sessions) > 1:
                raise ClaimError("%s: --strict: combines sessions %s" % (cid, sorted(sessions)))
            try:
                v = float(eval(c["extract"], {"__builtins__": {}, "abs": abs, "min": min, "max": max}, env))
            except Exception as e:
                raise ClaimError("%s: formula %r: %s" % (cid, c["extract"], e))
        else:                                # cited, prose
            if kind == "prose" and strict:
                raise ClaimError("%s: --strict: no raw data behind this number" % cid)
            if not c["value"]:
                raise ClaimError("%s: %s claims carry their value" % (cid, kind))
            if kind == "cited" and not c["notes"]:
                raise ClaimError("%s: cited claims need a reference in notes" % cid)
            v = float(c["value"])
        values[cid] = v
        return v

    for cid in by_id:
        value_of(cid)
    return by_id, values


def render_published(by_id, values):
    lines = ["id,value,units,kind"]
    for cid, c in by_id.items():
        lines.append("%s,%.10g,%s,%s" % (cid, values[cid], c["units"], c["kind"]))
    return "\n".join(lines) + "\n"


def render_numbers(by_id, values):
    out = ["% generated by reproduce/make_numbers.py from reproduce/claims.csv -- do not edit",
           "% \\claim{id} prints a published value; an unknown id stops the build."]
    for cid, c in by_id.items():
        out.append("\\expandafter\\def\\csname claim@%s\\endcsname{%s}"
                   % (cid, fmt(values[cid], c["format"])))
    out.append("\\providecommand{\\claim}[1]{\\ifcsname claim@#1\\endcsname"
               "\\csname claim@#1\\endcsname\\else\\errmessage{claim #1 undefined}\\fi}")
    return "\n".join(out) + "\n"


WHERE_TEXT = {
    "abstract": "abstract",
    "readme": "README",
    "sec:3": "results text",
    "sec:5": "impact text",
    "sec:6": "conclusions",
    "tab:cuda": "single-compartment speedups (table)",
    "tab:multicomp": "dendritic-tree speedups (table)",
    "fig:multicomp_speedup": "dendritic-tree speedups (figure)",
    "tab:mcksweep": "speedup against run length (table)",
    "tab:coreneuron": "spiking network against NEURON and CoreNEURON (table)",
    "tab:mccross": "dendritic trees against NEURON and Arbor (table)",
    "fig:crossover": "GPU crossover with Arbor (figure)",
    "fig:construction_scaling": "model construction (figure)",
    "fig:vmequiv": "membrane-potential equivalence (figure)",
}


def render_table(by_id):
    stages = {}
    for c in by_id.values():
        if c["kind"] == "derived":
            continue
        key = c["stage"] if c["kind"] != "prose" else ""
        s = stages.setdefault(key, {"n": 0, "hw": set(), "min": 0, "where": set()})
        s["n"] += 1
        s["hw"].add(c["hardware"])
        s["min"] = max(s["min"], int(c["minutes"] or 0))
        for w in c["where"].split(";"):
            if w:
                s["where"].add(WHERE_TEXT.get(w, w))
    rows = ["| Numbers | Where they appear | Script that measures them | Needs | Time |",
            "|---:|---|---|---|---|"]
    for key in sorted(stages, key=lambda k: (k == "", k)):
        s = stages[key]
        where = "; ".join(sorted(s["where"]))
        if key == "":
            rows.append("| %d | %s | none yet: typed into the paper with no raw data kept; "
                        "re-measured by the revision campaign | - | - |" % (s["n"], where))
            continue
        hw = ", ".join(HARDWARE_TEXT[h] for h in sorted(s["hw"]))
        rows.append("| %d | %s | `%s` | %s | %s |"
                    % (s["n"], where, key, hw, "%d min" % s["min"] if s["min"] else "-"))
    return "\n".join(rows)


def with_table(readme, table):
    if TABLE_BEGIN not in readme or TABLE_END not in readme:
        return readme
    head, rest = readme.split(TABLE_BEGIN, 1)
    _, tail = rest.split(TABLE_END, 1)
    return head + TABLE_BEGIN + "\n" + table + "\n" + TABLE_END + tail


def with_inline(readme, by_id, values):
    def sub(m):
        cid = m.group(1)
        if cid not in by_id:
            raise ClaimError("README.md: <!--claim:%s--> names no claim" % cid)
        return "<!--claim:%s-->%s<!--/claim-->" % (cid, fmt(values[cid], by_id[cid]["format"]))
    return INLINE_RE.sub(sub, readme)


def main(argv):
    check = "--check" in argv
    strict = "--strict" in argv
    try:
        by_id, values = evaluate(load_claims(), strict)
    except ClaimError as e:
        print("make_numbers: %s" % e, file=sys.stderr)
        return 1

    with open(README) as f:
        readme = f.read()
    outputs = {
        PUBLISHED: render_published(by_id, values),
        NUMBERS: render_numbers(by_id, values),
    }
    try:
        outputs[README] = with_table(with_inline(readme, by_id, values), render_table(by_id))
    except ClaimError as e:
        print("make_numbers: %s" % e, file=sys.stderr)
        return 1
    changed = []
    for path, text in outputs.items():
        old = open(path).read() if os.path.exists(path) else None
        if old != text:
            changed.append(os.path.relpath(path, ROOT))
            if not check:
                with open(path, "w") as f:
                    f.write(text)

    kinds = {}
    for c in by_id.values():
        kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
    print("%d claims (%s)" % (len(by_id), ", ".join("%d %s" % (n, k) for k, n in sorted(kinds.items()))))
    if kinds.get("prose"):
        print("%d claims have no raw data behind them yet (kind prose)" % kinds["prose"])
    if check:
        if changed:
            print("would change: " + ", ".join(changed))
            return 1
        print("no changes")
    elif changed:
        print("wrote: " + ", ".join(changed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
