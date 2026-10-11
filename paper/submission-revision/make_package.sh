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
#                                        rebuilt from an empty directory to prove it compiles
# With <private dir> (softwarex-revision/), also <private dir>/submission/:
#   response_to_reviewers.pdf, cover_letter.pdf   from the Markdown letters, which stay
#                                        out of the public repository
#
# Refuses when a \pending value is left in the manuscript or a [bracketed]
# placeholder in a letter, unless DRAFT=1. LATEXMK names the latexmk to run
# (inside the VS Code flatpak: LATEXMK="flatpak-spawn --host latexmk").
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=$ROOT/paper; S=$P/submission-revision
PRIV=${1:-}
DRAFT=${DRAFT:-0}
LATEXMK=${LATEXMK:-latexmk}
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
rm -f "$S/latex_source.zip"
( cd "$Z" && zip -q -X "$S/latex_source.zip" ./* )
T=$(mktemp -d "$ROOT/../.mktest.XXXXXX")
( cd "$T" && unzip -q "$S/latex_source.zip" )
$LATEXMK -pdf -interaction=nonstopmode -halt-on-error -cd "$T/manuscript_softwarex_revision.tex" > "$T/latexmk.out" 2>&1 \
    || { echo "REFUSED: latex_source.zip does not compile on its own" >&2; exit 1; }
echo "latex_source.zip: $(unzip -l "$S/latex_source.zip" | tail -1 | awk '{print $2}') files, compiles on its own"

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
