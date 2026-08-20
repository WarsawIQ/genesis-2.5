# SoftwareX submission package

Built 2026-08-20 from `paper/manuscript_softwarex_submission.tex`.

## Upload now, at first submission

| file | item type | note |
|---|---|---|
| `manuscript_softwarex_submission.pdf` | Manuscript | 21 pages, built from the source below |
| `highlights.txt` | Highlights | 5 bullets, each under the 85-character limit |
| `fig*.png` | Figure | one per figure, in order; also inside the PDF |
| `declarationStatement.docx` | Declaration of Interest | **regenerate from the declarations tool in Editorial Manager** -- the copy here is from the earlier submission |

## Keep for the revision stage

`latex_source.zip` -- the `.tex` and `figures/`, which is everything the PDF
needs. Verified by building in an empty directory: 21 pages, no undefined
references, no missing inputs. No `.bib` file is involved; the bibliography is
inline in the `.tex`.

## Checked against the guide for authors

- 3960 words of main text, against the 4000-word limit
- abstract 186 words, against 250
- 7 keywords, against 1-7
- highlights 5 bullets, all under 85 characters
- every figure used is at least 1772 px across, the single-column minimum
- CRediT statement, competing-interest declaration and funding statement present
- generative-AI declaration titled as the guide words it, in a section
  immediately before the references

## Still to confirm before sending

- the funding sentence says no specific grant; change it if that is wrong
- CRediT roles, which are the authors' to agree
- the Zenodo DOI in metadata field C2 points at an archive that predates the
  fixes this paper reports; cut a new release and update C1/C2 first
