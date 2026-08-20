#!/usr/bin/env python3
"""Turn the two submission letters into LaTeX, for the subset of Markdown they use.

Not a general converter: it handles the headings, bold, inline code, rules,
em dashes and escaping that cover_letter.md and response_to_reviewers.md
actually contain, and raises if it meets anything it would silently mangle.
"""
import re, sys

def esc(t):
    # inline code first, so its contents are not escaped twice
    parts = re.split(r"(`[^`]*`)", t)
    out = []
    for i, p in enumerate(parts):
        if i % 2:
            body = p[1:-1]
            for a, b in (("\\", r"\textbackslash{}"), ("_", r"\_"), ("%", r"\%"),
                         ("&", r"\&"), ("#", r"\#"), ("$", r"\$"), ("{", r"\{"), ("}", r"\}")):
                body = body.replace(a, b)
            out.append(r"\texttt{" + body + "}")
        else:
            for a, b in (("\\", r"\textbackslash{}"), ("&", r"\&"), ("%", r"\%"),
                         ("_", r"\_"), ("#", r"\#"), ("$", r"\$"),
                         ("^", r"\textasciicircum{}"), ("~", r"\textasciitilde{}")):
                p = p.replace(a, b)
            # O(n^2) and the like read better set as maths
            p = re.sub(r"O\(n\\textasciicircum\{\}2\)", r"$O(n^2)$", p)
            p = re.sub(r"\*\*(.+?)\*\*", r"\\textbf{\1}", p)
            p = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"\\emph{\1}", p)
            p = p.replace(" -- ", " --- ")
            out.append(p)
    return "".join(out)

def convert(md, title):
    # Work paragraph by paragraph, not line by line: **bold** and *emphasis*
    # routinely span a wrapped line, and a line-wise pass leaves the markers
    # in the output as literal asterisks.
    blocks = re.split(r"\n\s*\n", md)
    lines = []
    for b in blocks:
        if b.strip().startswith(("#", "---")) or b.strip() == "":
            lines.extend(b.split("\n"))
        else:
            lines.append(" ".join(x.strip() for x in b.split("\n") if x.strip()))
        lines.append("")
    body = []
    for line in lines:
        s = line.rstrip()
        if s.startswith("# "):
            continue                              # the title comes from the preamble
        if s.startswith("## "):
            body.append(r"\section*{" + esc(s[3:]) + "}")
        elif s.startswith("### "):
            body.append(r"\subsection*{" + esc(s[4:]) + "}")
        elif s.strip() == "---":
            body.append(r"\medskip\hrule\medskip")
        elif s.startswith("| ") or s.startswith("|-"):
            sys.exit("table found; this converter does not do tables")
        elif not s.strip():
            body.append("")
        else:
            body.append(esc(s))
    return (
        "\\documentclass[11pt,a4paper]{article}\n"
        "\\usepackage[T1]{fontenc}\n\\usepackage[utf8]{inputenc}\n"
        "\\usepackage[margin=25mm]{geometry}\n\\usepackage{parskip}\n"
        "\\usepackage[hidelinks]{hyperref}\n\\usepackage{url}\n"
        "\\setlength{\\emergencystretch}{2em}\n"
        "\\title{\\vspace{-2em}" + esc(title) + "}\n\\date{}\n\\author{}\n"
        "\\begin{document}\n\\maketitle\\vspace{-3em}\n"
        + "\n".join(body) +
        "\n\\end{document}\n")

if __name__ == "__main__":
    src, out, title = sys.argv[1], sys.argv[2], sys.argv[3]
    open(out, "w", encoding="utf-8").write(convert(open(src, encoding="utf-8").read(), title))
    print("wrote", out)
