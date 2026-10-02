#!/usr/bin/env python3
"""List numbers in a LaTeX manuscript that are not generated from the claim map.

    python3 reproduce/lint_numbers.py paper/manuscript_softwarex_submission.tex

Every measured result in the paper must be printed by \\claim{id}, which reads
paper/numbers.tex, which make_numbers.py writes from the raw data. A number
typed by hand can drift from its data without anyone noticing; this finds
them. Numbers that are not results (model parameters such as 4000 cells or
dt = 0.05 ms, version numbers, years, references) are allowed by the patterns
in reproduce/lint_allow.txt, one per line, each with the reason it is allowed.

Only the body is checked: the preamble, comments, \\claim{}, citations,
labels, references, URLs, file paths, code (\\texttt) and the bibliography
are skipped.

Exit 0 when every remaining number is allowed, 1 otherwise (each one listed as
file:line: number  context). Plain Python 3.6, standard library only.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ALLOW = os.path.join(HERE, "lint_allow.txt")

# Commands whose argument is never a result. \claim is the point of the lint.
SKIP_ARG = ("claim", "cite", "citep", "citet", "ref", "eqref", "label", "url",
            "path", "texttt", "href", "includegraphics", "hspace", "vspace",
            "setlength", "addtolength", "ead", "address", "author", "doi",
            "begin", "end", "multicolumn", "multirow", "cline", "arraystretch",
            "renewcommand", "setcounter", "resizebox", "rule", "fontsize")
SKIP_RE = re.compile(r"\\(?:%s)\*?(?:\[[^\]]*\])*(?:\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})+"
                     % "|".join(SKIP_ARG))
OPT_RE = re.compile(r"\[(?:width|height|scale|angle|trim)=[^\]]*\]")
COMMENT_RE = re.compile(r"(?<!\\)%.*$")
# 160\,000 and 160{,}000 are one number; so are 1.5 and 10^{-7}.
NUM_RE = re.compile(r"(?<![A-Za-z0-9_.@])\d+(?:(?:\\,|\{,\}|,)\d{3})*(?:\.\d+)?")


def load_allow(path):
    rules = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            pattern, _, reason = line.partition("\t#")
            if not reason.strip():
                raise SystemExit("%s:%d: every pattern needs a reason after <TAB>#" % (path, n))
            rules.append(re.compile(pattern.strip()))
    return rules


def body_lines(text):
    """Yield (line number, text) for the document body, comments removed."""
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if "\\begin{document}" in l), -1) + 1
    for i in range(start, len(lines)):
        if "\\end{document}" in lines[i] or "\\begin{thebibliography}" in lines[i]:
            break
        yield i + 1, COMMENT_RE.sub("", lines[i])


def lint(path, rules):
    found = []
    with open(path) as f:
        text = f.read()
    for n, line in body_lines(text):
        clean = OPT_RE.sub(" ", SKIP_RE.sub(" ", line))
        for m in NUM_RE.finditer(clean):
            lo, hi = max(0, m.start() - 40), min(len(clean), m.end() + 40)
            context = clean[lo:hi]
            window = (context[:m.start() - lo] + "\u2588" + m.group(0)
                      + "\u2588" + context[m.end() - lo:])
            if any(r.search(window) for r in rules):
                continue
            found.append((n, m.group(0), context.strip()))
    return found


def main(argv):
    if not argv:
        print(__doc__.strip().split("\n")[2].strip(), file=sys.stderr)
        return 2
    rules = load_allow(ALLOW)
    bad = 0
    for path in argv:
        for n, num, context in lint(path, rules):
            print("%s:%d: %s\t%s" % (path, n, num, context))
            bad += 1
    if bad:
        print("%d number(s) not from the claim map and not allowed" % bad, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
