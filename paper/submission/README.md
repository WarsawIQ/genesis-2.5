# SoftwareX submission package

Built 2026-08-20, revised 2026-08-23 after Editorial Manager sent the
resubmission (SOFTX-S-26-01564) back with three requests, from
`paper/manuscript_softwarex_submission.tex`.

## What changed 2026-08-23

Editorial Manager's "Send Back to Author" note asked for three things:

1. **In-text references not compiled properly.** The template's boilerplate
   `\label{}` (no key) had been left under most `\section*{}` headings and
   under one table caption -- nine copies of the same empty label, which
   LaTeX reports as "multiply defined". Nothing `\ref{}`'d them, so no wrong
   number was ever visible, but the warning is exactly what a formatting
   check like this flags. Removed all nine; the manuscript now compiles with
   no label warnings at all.
2. **Remove reviewer comments and place this into your cover letter.** This
   is technically a new submission (SOFTX-D-26-00952 was rejected outright,
   not sent back for revision), so a standalone "Response to Reviewers"
   attachment doesn't fit Editorial Manager's model for it: there is no
   assigned reviewer to respond to yet. Folded the whole point-by-point
   response into `cover_letter.md`/`.tex` instead, under a "Point-by-point
   response to the earlier review" heading. `response_to_reviewers.{md,tex,pdf}`
   are retired to `paper/archive/superseded_submission_2026-08/` -- do not
   attach them.
3. **Ensure sectioning follows the template.** The macro-structure (Required
   Metadata, Current code version, the five numbered sections, Software
   description's Architecture/Functionalities sub-items) was already correct.
   The one real deviation: "Declaration of generative AI..." sat after
   Acknowledgements instead of beside the other declarations. Elsevier's
   current standard order is CRediT -> Declaration of competing interest ->
   Declaration of generative AI -> Funding -> Acknowledgements -> References;
   moved it there.

## Upload now

| file | item type | note |
|---|---|---|
| `manuscript_softwarex_submission.pdf` | Manuscript | 21 pages, built from the source below |
| `highlights.txt` | Highlights | 5 bullets, each under the 85-character limit |
| `fig*.png` | Figure | one per figure, in order; also inside the PDF |
| `cover_letter.pdf` | Cover Letter | resubmission of SOFTX-D-26-00952, now including the point-by-point response, 4 pages |
| `editorial_comments.txt` | _(not a file upload)_ | paste into the "Comments to the editorial office" box |
| _declaration of interest_ | Declaration of Interest | **generate it from the declarations tool in Editorial Manager.** Not kept in the repository: it is correspondence about the work, not the work |

Do **not** attach a separate "Response to Reviewers" file this time -- remove
it from the file list in Editorial Manager if it is still listed from the
prior attempt, and upload the new `cover_letter.pdf` in its place.

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

## Sources kept beside the PDFs

`cover_letter.md` is the text; `md2tex.py` converts it and `cover_letter.tex`
is what pdflatex builds. Edit the Markdown and re-run the converter rather
than the `.tex`. `response_to_reviewers.md` is superseded -- its content now
lives inside `cover_letter.md` -- and stays only in
`paper/archive/superseded_submission_2026-08/` for the record.
