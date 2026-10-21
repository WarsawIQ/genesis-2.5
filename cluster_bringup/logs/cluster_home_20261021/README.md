# Files from the cluster home directory (miranda), 21 October 2026

Every regular file at the top of `~` on the UMCS cluster whose content is not
already somewhere in this repository's history (checked by git blob hash), so
that nothing measured or written there exists only on the cluster:
169 files, 126 from August, 10 from September, 33 from October 2026, among them
26 scripts (`.sh`, `.py`, `.g`). Most are build logs and one-off checks from the
bring-up and the campaign dry runs; the stages that measured the paper are in
`cluster_bringup/campaign/`, and their data in `cluster_bringup/logs/`.

- `home_files.tar.gz`: the files, flat, as they were (owner and times normalised).
- `INDEX.tsv`: name, size in bytes, last-modified date on the cluster.

- `out.dat.gz`: `~/out.dat` of 18 August, 592 865 spikes (time, cell): the
  spike file of the first submission's CoreNEURON GPU run, whose spike count the
  rebuilt toolchain reproduced (`cluster_bringup/coreneuron/README.md`).

Left out: dotfiles (shell history and settings), and six files over 5 MB that
are copies of what is kept elsewhere: the git bundles `f0`, `f1`, `rev`, `up`
(of this repository and its branches), `genesis-2.5.1-Linux-bin.tar.gz` (the
v2.5.1 release asset) and `miniforge.sh` (the installer). Directories under `~`
are not covered here.

The four v2.6.2 gate clones (`~/gate-262-inf0?`, `~/gate-base-262-inf0?`) held
nothing that is not in the repository: their 24 result files are identical to
`cluster_bringup/logs/verify_against_base/inf0?_20261018_*`,
`campaign_v2.6.2/` and `release/v2.6.2/`; their wrapper logs are
`verify_against_base/gate-262-inf0?.log`.
