# External toolchains for the cross-simulator comparison

GENESIS itself needs only GCC, make and (for the GPU backends) a CUDA toolkit or an OpenCL
runtime; see the top-level README. This directory builds the *other* simulators the paper
compares against, at the exact versions it used (`../../reproduce/VERSIONS`). Nothing here is
needed to use GENESIS 2.5.

All locations come from `../env.sh`. To rebuild everything from nothing, point `WORK_DIR` at
an empty directory:

```sh
export WORK_DIR=$HOME/toolchains-fresh
sh cluster_bringup/toolchains/fetch_modeldb_83319.sh   # ModelDB 83319, checksum-verified
bash cluster_bringup/toolchains/10_miniforge.sh          # Python 3.13 with headers
bash cluster_bringup/toolchains/20_nvhpc.sh              # NVHPC 24.11 (6.1 GB download)
bash cluster_bringup/toolchains/30_neuron_gpu.sh         # NEURON 9.0.2 + CoreNEURON GPU
bash cluster_bringup/toolchains/40_arbor_gpu.sh          # Arbor 0.10.0 with CUDA
bash cluster_bringup/coreneuron/build_mechanisms.sh      # COBAHH channels, CPU and GPU
```

The NEURON CPU arms use the pip wheel: `python3.12 -m pip install --user neuron==9.0.2`.

Every recipe verifies its downloads against a checksum, refuses a source tree at the wrong
commit, and exits at once if its result is already installed, so re-running is safe.

| Recipe | Time (estimate, replaced by the measured one after the verification build) | Disk |
|---|---|---|
| `10_miniforge.sh` | 2 min | 0.5 GB |
| `20_nvhpc.sh` | 20 min | 6.1 GB download, 13 GB installed |
| `30_neuron_gpu.sh` | 1–2 h | 1 GB |
| `40_arbor_gpu.sh` | 30–60 min | 1 GB |

## Why the builds look the way they do

Each of these cost a day to find. They are recorded so that nobody has to find them again.

- **NVHPC 24.11, not the current release.** nvc++ 25.3 miscompiles NEURON's `nocmodl` code
  generator, which then segfaults on every `.mod` file. 24.11 is what NEURON's own CI uses.
- **Both code generators are built with GCC.** Under NVHPC 24.11 `nocmodl` and `nmodl` still
  segfault. They are host tools that emit C++; the device code is compiled by nvc++ afterwards
  whoever built them, so building them with GCC changes nothing that runs on the GPU.
  `30_neuron_gpu.sh` builds them first and puts them in the GPU tree before it needs them.
- **The NVHPC-built NEURON is used for CoreNEURON only.** Its Python module segfaults on
  import and `nrniv` crashes on a single passive soma. CoreNEURON does not need NEURON at run
  time: the pip NEURON writes the model out with `nrncore_write`, and `special-core` reads and
  simulates it on the GPU (`../coreneuron/coreneuron_gpu_standalone.sh`). For the same reason
  `make install` is not run; the build tree is used directly.
- **`-lstdc++fs` on the GPU mechanisms.** Without it `special-core` fails to load with an
  undefined `std::filesystem` symbol: GCC 8.5's `libstdc++.so` does not export it and
  `libstdc++fs` exists only as a static archive.
- **System CMake 3.26 and gcc-toolset-13.** The pip CMake 4 that comes first on `PATH` on the
  UMCS login node cannot build Arbor 0.10 (CMake 4 removed `find_package(CUDA)`, which it
  calls). Arbor 0.12 in turn requires CMake 4, which is why the paper uses 0.10.0.
- **Arbor's CPU target is pinned to `icelake-server`.** Arbor builds with `-march=native` by
  default. The paper's build was made on a GPU node and dies with `Illegal instruction` on the
  older login node; built natively on the login node it would lose AVX-512 on the GPU nodes and
  run the Arbor CPU arm slower than the paper measured.
- **The Arbor that `python3.12` imports on the cluster is the wrong one.** A pip Arbor 0.12.2
  without GPU support is installed there. Every Arbor arm runs with `$ARBOR_PYTHON` and
  `PYTHONPATH=$ARBOR_PY`, and checks the version before timing.

## Provenance

These recipes were derived from scripts that existed only in a home directory on the UMCS
cluster. The originals are in `as-found/`, unchanged, with their checksums in
`AS_FOUND.sha256`; `AUDIT_2026-09-29.md` records what each one did and where it went.
