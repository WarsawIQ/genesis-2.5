#!/bin/sh
# Build the files to upload for the revision of SOFTX-D-26-01093.
#
#     sh paper/submission-revision/make_package.sh [<private dir>]
#
# Into paper/submission-revision/:
#   manuscript_softwarex_revision.pdf   compiled from paper/manuscript_softwarex_revision.tex
#   highlights.txt                       highlights.in with {{claim id}} replaced by the
#                                        published value; 3-5 bullets of at most 85 characters
#   abstract.txt                         the manuscript's abstract with its values, as plain text
#   latex_source.zip                     the .tex, numbers.tex, bibliography.tex and the
#                                        figures, flat (Editorial Manager refuses subfolders),
#                                        without the %% working comments, rebuilt from an
#                                        empty directory to prove it compiles
#   em/                                  what Editorial Manager's revision asks for: the
#                                        manuscript as one editable .tex with PNG figures,
#                                        and manuscript_marked_up.pdf against the reviewed
#                                        version (REVIEWED, default 4452b40 of 23 August)
# With <private dir> (softwarex-revision/), also <private dir>/submission/:
#   response_to_reviewers.pdf, cover_letter.pdf   from the Markdown letters, which stay
#                                        out of the public repository
#
# Refuses when a \pending value is left in the manuscript or a [bracketed]
# placeholder in a letter, unless DRAFT=1. LATEXMK names the latexmk to run
# (inside the VS Code flatpak: LATEXMK="flatpak-spawn --host latexmk"); LATEXDIFF and
# PDFTOCAIRO likewise.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=$ROOT/paper; S=$P/submission-revision
PRIV=${1:-}
DRAFT=${DRAFT:-0}
LATEXMK=${LATEXMK:-latexmk}
LATEXDIFF=${LATEXDIFF:-latexdiff}
PDFTOCAIRO=${PDFTOCAIRO:-pdftocairo}
REVIEWED=${REVIEWED:-4452b40}
cd "$ROOT"

python3 reproduce/make_numbers.py --check > /dev/null
pend=$(grep -v '^ *%' "$P/manuscript_softwarex_revision.tex" | grep -c '\\pending{' || true)
echo "manuscript: $pend \\pending value(s) left"
[ "$pend" = 0 ] || [ "$DRAFT" = 1 ] || { echo "REFUSED: \\pending left (DRAFT=1 builds anyway)" >&2; exit 1; }

# 1. the manuscript
B=$(mktemp -d "$ROOT/../.mkpkg.XXXXXX")
$LATEXMK -pdf -interaction=nonstopmode -halt-on-error -outdir="$B" -cd "$P/manuscript_softwarex_revision.tex" > "$B/latexmk.out" 2>&1 \
    || { tail -30 "$B/latexmk.out"; echo "REFUSED: the manuscript does not compile" >&2; exit 1; }
cp "$B/manuscript_softwarex_revision.pdf" "$S/"

# 2. highlights and abstract, with the published values
python3 - "$ROOT" <<'PY'
import csv, re, sys
root = sys.argv[1]
sys.path.insert(0, root + "/reproduce")
from make_numbers import fmt
claims = {r["id"]: r for r in csv.DictReader(l for l in open(root + "/reproduce/claims.csv") if not l.startswith("#"))}
vals = {r["id"]: float(r["value"]) for r in csv.DictReader(open(root + "/reproduce/published.csv"))}
val = lambda k: fmt(vals[k], claims[k]["format"])
S = root + "/paper/submission-revision/"
hl = [re.sub(r"\{\{(\w+)\}\}", lambda m: val(m.group(1)), l.rstrip("\n"))
      for l in open(S + "highlights.in") if l.strip()]
if not 3 <= len(hl) <= 5:
    sys.exit("REFUSED: %d highlights, the guide asks for 3-5" % len(hl))
for h in hl:
    if len(h) > 85:
        sys.exit("REFUSED: highlight of %d characters (limit 85): %s" % (len(h), h))
open(S + "highlights.txt", "w").write("\n".join(hl) + "\n")
tex = open(root + "/paper/manuscript_softwarex_revision.tex").read()
a = tex[tex.index(r"\begin{abstract}") + 16:tex.index(r"\end{abstract}")]
a = "\n".join(l for l in a.split("\n") if not l.lstrip().startswith("%"))
a = re.sub(r"\\claim\{(\w+)\}", lambda m: val(m.group(1)), a)
a = re.sub(r"\$\\times\$", "x", a)
a = re.sub(r"\\texttt\{([^}]*)\}", r"\1", a)
a = a.replace("~", " ").replace(r"\,", " ").replace("\\", "")
a = " ".join(a.split())
open(S + "abstract.txt", "w").write(a + "\n")
print("highlights: %d, longest %d characters; abstract: %d words" % (len(hl), max(map(len, hl)), len(a.split())))
PY

# 3. the LaTeX source, flat, and proof that it compiles from an empty directory
Z=$(mktemp -d "$ROOT/../.mkzip.XXXXXX")
cp "$P/manuscript_softwarex_revision.tex" "$P/numbers.tex" "$P/bibliography.tex" "$P"/figures/fig_architecture.pdf \
   "$P"/figures/fig_trees.pdf "$P"/figures/fig_runlength.pdf "$P"/figures/fig_crossover.pdf \
   "$P"/figures/fig_construction.pdf "$Z/"
# the copy sent to the journal loses our %% working comments (word budgets,
# reviewer point numbers, notes to ourselves); the build below proves it still compiles
python3 - "$Z/manuscript_softwarex_revision.tex" <<'PY'
import re, sys
p = sys.argv[1]
out = [re.sub(r"\s*(?<!\\)%%.*$", "", l) for l in open(p).read().split("\n")
       if not l.lstrip().startswith("%%")]
open(p, "w").write("\n".join(out))
PY
rm -f "$S/latex_source.zip"
( cd "$Z" && zip -q -X "$S/latex_source.zip" ./* )
T=$(mktemp -d "$ROOT/../.mktest.XXXXXX")
( cd "$T" && unzip -q "$S/latex_source.zip" )
$LATEXMK -pdf -interaction=nonstopmode -halt-on-error -cd "$T/manuscript_softwarex_revision.tex" > "$T/latexmk.out" 2>&1 \
    || { echo "REFUSED: latex_source.zip does not compile on its own" >&2; exit 1; }
echo "latex_source.zip: $(unzip -l "$S/latex_source.zip" | tail -1 | awk '{print $2}') files, compiles on its own"

# 3b. what Editorial Manager asks of a revision: the manuscript as one editable
# .tex with its figures as PNG (it builds its own PDF; a PDF is refused), and a
# marked-up copy against the version the reviewers read (REVIEWED, 23 August)
E=$S/em; rm -rf "$E"; mkdir -p "$E"
D=$(mktemp -d "$ROOT/../.mkdiff.XXXXXX")
for f in fig_architecture fig_trees fig_runlength fig_crossover fig_construction; do
    $PDFTOCAIRO -png -r 600 -singlefile "$Z/$f.pdf" "$E/$f"
done
git show "$REVIEWED:paper/manuscript_softwarex_submission.tex" > "$D/old.tex"
for f in $(git ls-tree --name-only "$REVIEWED" paper/figures/ | grep '\.png$'); do
    git show "$REVIEWED:$f" > "$D/$(basename "$f")"
done
cp "$E"/*.png "$D/"
python3 - "$Z" "$E" "$D" <<'PY'
import re, sys
Z, E, D = sys.argv[1:]
src = open(Z + "/manuscript_softwarex_revision.tex").read()
num = open(Z + "/numbers.tex").read().rstrip("\n")
bib = open(Z + "/bibliography.tex").read().rstrip("\n")
png = lambda t: re.sub(r"(\\includegraphics(?:\[[^\]]*\])?\{fig_\w+)\.pdf\}", r"\1.png}", t)
# the editable copy: numbers.tex and bibliography.tex pasted in, figures as PNG
flat = src.replace("\\input{numbers}", num).replace("\\input{bibliography}", bib)
open(E + "/manuscript_softwarex_revision.tex", "w").write(png(flat))
# the diff's new side: every \claim written out, so a changed value shows as changed
vals = dict(re.findall(r"\\csname claim@(.+?)\\endcsname\{(.*)\}\s*$", num, re.M))
new = re.sub(r"\\claim\{([^}]+)\}", lambda m: vals[m.group(1)],
             src.replace("\\input{numbers}", "").replace("\\input{bibliography}", bib))
old = open(D + "/old.tex").read()
for name, t in (("old", old), ("new", png(new))):
    # latexdiff breaks elsarticle's frontmatter: abstract and keywords become sections
    out = []
    for env, head in (("abstract", "Abstract"), ("keyword", "Keywords")):
        m = re.search(r"\\begin\{%s\}(.*?)\\end\{%s\}" % (env, env), t, re.S)
        body = "\n".join(l for l in m.group(1).strip().split("\n") if not l.lstrip().startswith("%"))
        out.append("\\section*{%s}\n%s\n" % (head, body.replace("\\sep", ";")))
        t = t[:m.start()] + t[m.end():]
    i = t.index("\\end{frontmatter}") + len("\\end{frontmatter}")
    t = t[:i] + "\n\n" + "\n".join(out) + t[i:]
    # "$\sim$$10^{-7}$" reads to latexdiff as display math
    open("%s/%s_d.tex" % (D, name), "w").write(t.replace("$\\sim$$", "\\ensuremath{\\sim}$"))
PY
( cd "$D" && $LATEXDIFF --graphics-markup=none --math-markup=whole \
      --config="PICTUREENV=(?:picture|DIFnomarkup|tabular)[\w\d*@]*" old_d.tex new_d.tex > marked.tex 2> latexdiff.err ) \
    || { tail -5 "$D/latexdiff.err"; echo "REFUSED: latexdiff failed" >&2; exit 1; }
$LATEXMK -pdf -interaction=nonstopmode -halt-on-error -cd "$D/marked.tex" > "$D/latexmk.out" 2>&1 \
    || { tail -20 "$D/latexmk.out"; echo "REFUSED: the marked-up copy does not compile" >&2; exit 1; }
cp "$D/marked.pdf" "$E/manuscript_marked_up.pdf"
T2=$(mktemp -d "$ROOT/../.mktest.XXXXXX")
cp "$E"/*.tex "$E"/*.png "$T2/"
$LATEXMK -pdf -interaction=nonstopmode -halt-on-error -cd "$T2/manuscript_softwarex_revision.tex" > "$T2/latexmk.out" 2>&1 \
    || { tail -20 "$T2/latexmk.out"; echo "REFUSED: the editable copy does not compile on its own" >&2; exit 1; }
echo "em/: editable .tex and $(ls "$E"/*.png | wc -l) PNG figures compile on their own; marked-up copy against $REVIEWED"
rm -rf "$D" "$T2"

# 4. the letters, privately
if [ -n "$PRIV" ]; then
    O=$PRIV/submission; mkdir -p "$O"
    for pair in "response-to-reviewers.md:response_to_reviewers:Response to the reviewers, SOFTX-D-26-01093" \
                "cover-letter-revision.md:cover_letter:Cover letter, revision of SOFTX-D-26-01093"; do
        md=${pair%%:*}; rest=${pair#*:}; name=${rest%%:*}; title=${rest#*:}
        # the private draft note at the top of a letter is not sent
        awk 'BEGIN{skip=0} /^\*Draft/{skip=1} skip&&/^$/{skip=0; next} !skip' "$PRIV/$md" > "$B/$name.md"
        # a placeholder may wrap over lines; markdown links "[text](url)" are not placeholders
        left=$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); h=[m.group(0) for m in re.finditer(r"\[[^\]]*\](?!\()", t)]; print("\n".join(" ".join(x.split()) for x in h))' "$B/$name.md")
        nleft=$(printf '%s' "$left" | grep -c . || true)
        echo "$name: $nleft [bracketed] placeholder(s)${left:+: $(echo "$left" | tr '\n' ';')}"
        [ "$nleft" = 0 ] || [ "$DRAFT" = 1 ] || { echo "REFUSED: placeholders left in $md" >&2; exit 1; }
        python3 "$S/md2tex.py" "$B/$name.md" "$O/$name.tex" "$title" > /dev/null
        $LATEXMK -pdf -interaction=nonstopmode -halt-on-error -cd "$O/$name.tex" > "$B/$name.latexmk" 2>&1 \
            || { tail -20 "$B/$name.latexmk"; echo "REFUSED: $name does not compile" >&2; exit 1; }
        echo "$name.pdf written to $O"
    done
fi
rm -rf "$B" "$Z" "$T"
ls -la "$S"
