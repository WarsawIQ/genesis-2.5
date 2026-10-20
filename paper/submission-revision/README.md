# SoftwareX revision package (SOFTX-D-26-01093)

Built by `make_package.sh` from `paper/manuscript_softwarex_revision.tex` and the
claim map; rebuild it, do not edit the outputs:

    sh paper/submission-revision/make_package.sh <private dir>

It refuses while a `\pending` value is left in the manuscript or a `[bracketed]`
placeholder in a letter (`DRAFT=1` builds anyway). The letters are correspondence
about the work, so their Markdown and PDFs live in the private directory, not
here.

## Upload

Editorial Manager refuses a PDF as the revised manuscript: it wants the
editable source, from which it builds its own PDF, and a copy with the changes
marked. `make_package.sh` writes both into `em/`.

| file | item type | note |
|---|---|---|
| `em/manuscript_softwarex_revision.tex` | Revised manuscript (unmarked, editable source file) | one file: `numbers.tex` and `bibliography.tex` pasted in, figures referenced as PNG |
| `em/fig_architecture.png` ... `em/fig_construction.png` | Figure | Figures 1-5 in this order: architecture, trees, runlength, crossover, construction (600 dpi) |
| `em/manuscript_marked_up.pdf` | Revised manuscript (marked up) | latexdiff against the version the reviewers read (4452b40, 23 August), with every number written out |
| `highlights.txt` | Highlights (in the first submission: Supplementary material) | 3-5 bullets, each at most 85 characters, values from the claim map |
| `<private>/submission/response_to_reviewers.pdf` | Response to Reviewers | point by point; the review panel also takes a reply under each reviewer |
| `<private>/submission/cover_letter.pdf` | Cover Letter | |
| `abstract.txt` | _(not a file)_ | paste into the abstract field |
| declaration of competing interests | Declaration of competing interests | the statement from the first submission, kept ("Include in Revision") |

`manuscript_softwarex_revision.pdf` and `latex_source.zip` are the same
manuscript as we build it, for reading and for anyone who wants the source with
`numbers.tex` and `bibliography.tex` apart.

Limits, from the SoftwareX Original Software Publication template of 2026
(`paper/docs/softwarex-osp-template.tex`): 4000 words, at most 6 figures, an
abstract of about 100 words.

`paper/submission/` is the package of the first submission (2026-08), kept as
it was.
