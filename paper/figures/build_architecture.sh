#!/bin/sh
# Build Fig. 1 (fig_architecture.pdf) from fig_architecture.tex. Needs pdflatex with TikZ.
set -eu
cd "$(dirname "$0")"
pdflatex -interaction=nonstopmode -halt-on-error fig_architecture.tex > /dev/null
rm -f fig_architecture.aux fig_architecture.log
echo "written: $(pwd)/fig_architecture.pdf"
