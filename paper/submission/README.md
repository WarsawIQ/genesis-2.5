# SoftwareX submission package

Built 2026-08-20 from `paper/manuscript_softwarex_submission.tex`.

## Upload now, at first submission

| file | item type | note |
|---|---|---|
| `manuscript_softwarex_submission.pdf` | Manuscript | 21 pages, built from the source below |
| `highlights.txt` | Highlights | 5 bullets, each under the 85-character limit |
| `fig*.png` | Figure | one per figure, in order; also inside the PDF |
| `response_to_reviewers.md` | Response to Reviewers | point-by-point reply to SOFTX-D-26-00952 |
| `cover_letter.md` | Cover Letter | resubmission of SOFTX-D-26-00952; paste as plain text |
| _declaration of interest_ | Declaration of Interest | **generate it from the declarations tool in Editorial Manager.** Not kept in the repository: it is correspondence about the work, not the work |

## Keep for the revision stage

`latex_source.zip` -- the `.tex` and the six figures, flat, with no directory
structure: Editorial Manager refuses a zip containing subfolders. The manuscript
still finds its figures because `\graphicspath` adds `figures/` to the search
path rather than replacing the current directory, so both layouts build.
Verified by extracting into an empty directory and building: 21 pages, no
undefined references, no missing graphics. No `.bib` file is involved; the
bibliography is inline in the `.tex`.

## Checked against the guide for authors

- 3960 words of main text, against the 4000-word limit
- abstract 186 words, against 250
- 7 keywords, against 1-7
- highlights 5 bullets, all under 85 characters
- every figure used is at least 1772 px across, the single-column minimum
- CRediT statement, competing-interest declaration and funding statement present
- generative-AI declaration titled as the guide words it, in a section
  immediately before the references
