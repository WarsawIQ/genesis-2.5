#!/bin/sh
# Build Fig. 1 (fig_architecture.pdf, and a PNG for the README) from
# fig_architecture.tex. Needs pdflatex with TikZ and pdftoppm (poppler).
set -eu
cd "$(dirname "$0")"
pdflatex -interaction=nonstopmode -halt-on-error fig_architecture.tex > /dev/null
rm -f fig_architecture.aux fig_architecture.log
# a PNG of the same figure for the README (GitHub does not show PDFs inline)
pdftoppm -png -r 200 -singlefile fig_architecture.pdf fig_architecture
echo "written: $(pwd)/fig_architecture.pdf and fig_architecture.png"
