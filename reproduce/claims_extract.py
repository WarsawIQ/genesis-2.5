"""Compute each published value from the raw data it comes from.

reproduce/claims.csv names, for every measured claim, an extractor and the
selection it applies. Nothing here knows about particular claims: the
extractors are generic, and the claim map says what to feed them. That keeps
the values honest -- a number in the paper is whatever this code computes from
the data in the repository, not what someone typed.

One definition of uncertainty is used throughout: a speedup is the ratio of
the two arms' means, and its uncertainty the relative sample standard
deviations of both arms combined in quadrature. The first submitted version
of the paper mixed three definitions under the one label "mean +/- std"; this
is the one the revision uses everywhere.

Plain Python 3.6, standard library only, like compare.py: the cluster's system
Python is 3.6.
"""

import csv
import math
import re
import statistics


class ExtractError(Exception):
    pass


def _rows(path):
    with open(path, newline="") as f:
        lines = [l for l in f if not l.startswith("#")]
    return list(csv.DictReader(lines))


def _parse_filter(spec):
    """'mode=cpu;n_neurons=500' -> {'mode': 'cpu', 'n_neurons': '500'}"""
    out = {}
    if not spec:
        return out
    for part in spec.split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise ExtractError("bad filter term %r" % part)
        k, v = part.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def _select(rows, flt, path):
    for k in flt:
        if rows and k not in rows[0]:
            raise ExtractError("%s has no column %r" % (path, k))
    return [r for r in rows if all(r[k] == v for k, v in flt.items())]


def _values(path, col, select, extra=""):
    rows = _rows(path)
    flt = _parse_filter(select)
    flt.update(_parse_filter(extra))
    sel = _select(rows, flt, path)
    if not sel:
        raise ExtractError("%s: no rows match %s" % (path, flt))
    if col not in sel[0]:
        raise ExtractError("%s has no column %r" % (path, col))
    return [float(r[col]) for r in sel]


def _rel_sd(v):
    return statistics.stdev(v) / statistics.mean(v) if len(v) > 1 else 0.0


# --------------------------------------------------------------- extractors
# Each takes the claim row (a dict) and returns a float.

def mean(c):
    return statistics.mean(_values(c["data"], c["col"], c["select"]))


def sd(c):
    return statistics.stdev(_values(c["data"], c["col"], c["select"]))


def count(c):
    return float(len(_values(c["data"], c["col"], c["select"])))


def ratio(c):
    """Ratio of the means of two arms of one file (num / den)."""
    n = _values(c["data"], c["col"], c["select"], c["num"])
    d = _values(c["data"], c["col"], c["select"], c["den"])
    return statistics.mean(n) / statistics.mean(d)


def ratio_sd(c):
    """Uncertainty of ratio(): relative sample SDs in quadrature."""
    n = _values(c["data"], c["col"], c["select"], c["num"])
    d = _values(c["data"], c["col"], c["select"], c["den"])
    r = statistics.mean(n) / statistics.mean(d)
    return r * math.sqrt(_rel_sd(n) ** 2 + _rel_sd(d) ** 2)


def _fit(xs, ys):
    """Least-squares line y = a + b x."""
    n = float(len(xs))
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        raise ExtractError("cannot fit a line to a single x value")
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return my - b * mx, b


def _arm_xy(c, extra):
    rows = _select(_rows(c["data"]),
                   dict(_parse_filter(c["select"]), **_parse_filter(extra)),
                   c["data"])
    if not rows:
        raise ExtractError("%s: no rows for %s" % (c["data"], extra))
    xcol = c["x"]
    return [float(r[xcol]) for r in rows], [float(r[c["col"]]) for r in rows]


def crossover(c):
    """x at which the fitted lines of arms num and den cross.

    Refuses a crossing outside the measured range of x: that is an
    extrapolation, not a measurement, and a crossing at negative x means the
    two arms never cross at all (one is slower at every length measured).
    """
    x1, y1 = _arm_xy(c, c["num"])
    x2, y2 = _arm_xy(c, c["den"])
    a1, b1 = _fit(x1, y1)
    a2, b2 = _fit(x2, y2)
    if b1 == b2:
        raise ExtractError("parallel lines never cross")
    x = (a2 - a1) / (b1 - b2)
    lo, hi = min(x1 + x2), max(x1 + x2)
    if not lo <= x <= hi:
        raise ExtractError("the lines cross at x = %.4g, outside the measured range "
                           "%g-%g: no crossover was measured" % (x, lo, hi))
    return x


def first_above(c):
    """Smallest x from which the ratio of the means of num and den stays above 1.

    For each measured x the ratio is mean(num) / mean(den) over the rows at
    that x (num = the CPU arm and den = the accelerated one gives the speedup).
    The value is the first x of the measured sweep at which the ratio exceeds 1
    and stays above 1 at every larger x. Refused when the ratio is above 1 at
    the smallest x (the threshold was not measured, only bounded) or never ends
    above 1.
    """
    xn, yn = _arm_xy(c, c["num"])
    xd, yd = _arm_xy(c, c["den"])
    xs = sorted(set(xn) & set(xd))
    if len(xs) < 2:
        raise ExtractError("first_above needs at least two common x values")
    above = []
    for x in xs:
        n = [y for xx, y in zip(xn, yn) if xx == x]
        d = [y for xx, y in zip(xd, yd) if xx == x]
        above.append(statistics.mean(n) / statistics.mean(d) > 1.0)
    if not above[-1]:
        raise ExtractError("the ratio is not above 1 at the largest x, %g" % xs[-1])
    i = len(above) - 1
    while i > 0 and above[i - 1]:
        i -= 1
    if i == 0:
        raise ExtractError("the ratio is above 1 already at the smallest x, %g: "
                           "the threshold lies below the measured range" % xs[0])
    return xs[i]


def intercept(c):
    return _fit(*_arm_xy(c, c["num"]))[0]


def slope(c):
    return _fit(*_arm_xy(c, c["num"]))[1]


def loglog_slope(c):
    """Scaling exponent: slope of log(col) against log(x) for arm num."""
    xs, ys = _arm_xy(c, c["num"])
    return _fit([math.log(x) for x in xs], [math.log(y) for y in ys])[1]


def regex(c):
    """First capture group of the pattern in `select`, from a text file."""
    with open(c["data"], errors="replace") as f:
        text = f.read()
    m = re.search(c["select"], text)
    if not m:
        raise ExtractError("%s: pattern %r not found" % (c["data"], c["select"]))
    return float(m.group(1).replace(",", ""))


EXTRACTORS = {
    "mean": mean, "sd": sd, "count": count,
    "ratio": ratio, "ratio_sd": ratio_sd,
    "crossover": crossover, "first_above": first_above, "intercept": intercept, "slope": slope,
    "loglog_slope": loglog_slope, "regex": regex,
}


def extract(claim):
    fn = EXTRACTORS.get(claim["extract"])
    if fn is None:
        raise ExtractError("unknown extractor %r" % claim["extract"])
    return fn(claim)
