# SoftwareX revision package (SOFTX-D-26-01093)

Built by `make_package.sh` from `paper/manuscript_softwarex_revision.tex` and the
claim map; rebuild it, do not edit the outputs:

    sh paper/submission-revision/make_package.sh <private dir>

It refuses while a `\pending` value is left in the manuscript or a `[bracketed]`
placeholder in a letter (`DRAFT=1` builds anyway). The letters are correspondence
about the work, so their Markdown and PDFs live in the private directory, not
here.

## Upload

| file | item type | note |
|---|---|---|
| `manuscript_softwarex_revision.pdf` | Manuscript | the revised manuscript |
| `highlights.txt` | Highlights | 3-5 bullets, each at most 85 characters, values from the claim map |
| `latex_source.zip` | LaTeX source | flat (Editorial Manager refuses subfolders): the `.tex`, `numbers.tex`, `bibliography.tex` and the five figures; `make_package.sh` compiles it from an empty directory |
| `<private>/submission/response_to_reviewers.pdf` | Response to Reviewers | point by point |
| `<private>/submission/cover_letter.pdf` | Cover Letter | |
| `abstract.txt` | _(not a file)_ | paste into the abstract field |
| declaration of interest | Declaration of Interest | generate it with the declarations tool in Editorial Manager |

Limits, from the SoftwareX Original Software Publication template of 2026
(`paper/docs/softwarex-osp-template.tex`): 4000 words, at most 6 figures, an
abstract of about 100 words.

`paper/submission/` is the package of the first submission (2026-08), kept as
it was.
