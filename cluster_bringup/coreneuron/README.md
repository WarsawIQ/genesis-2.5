# CoreNEURON head-to-head comparison

Reviewer 2 of SOFTX-D-26-00952 asked for a head-to-head against CoreNEURON.
This directory holds what is needed to reproduce that comparison on the
Vogels-Abbott COBAHH network, the same model GENESIS runs as VAnet2.

## The model

ModelDB accession 83319 (Brette et al., *J Comput Neurosci* 23:349, 2007),
directory `NEURON/cobahh`. 4000 cells, 320\,000 connections. To match VAnet2 we
set `dt = 0.05` ms and `tstop = 5000` ms in `common/init.hoc`; the package
default is `dt = 0.1`, which halves the work and is not comparable.

## Why the stock benchmark cannot run under CoreNEURON

The sodium and potassium channels `nahh` and `khh` are not NMODL files. They are
**ChannelBuilder** channels, serialised as GUI state in `cobahh/hhchan.ses` and
reconstructed at run time inside the NEURON interpreter (`KSChan` objects).

CoreNEURON has no interpreter. It requires every mechanism to exist as compiled
NMODL, so `nrn_setup` aborts:

```
coreneuron::hoc_execerror("nahh", "mechanism does not exist")
  in coreneuron::create_tml
  in coreneuron::Phase2::populate
```

The abort message is emitted inside an OpenMP region and is lost from stderr;
the visible symptom is a bare `Aborted` (SIGABRT) right after
`Memory (MBs) : Before nrn_setup`. Recovering the string needs a breakpoint on
`coreneuron::hoc_execerror`.

This is a property of the benchmark, not of CoreNEURON: a model whose channels
are written in NMODL is unaffected.

## What this directory supplies

`mechanisms/nahh.mod`, `mechanisms/khh.mod` transcribe the two ChannelBuilder
channels into NMODL. The `.ses` file stores each rate as an `(A, k, vh)` triple
plus a type code, and the transcription is exact:

| gate | rate | `.ses` type and triple | expression |
|------|------|------------------------|------------|
| m (^3) | alpha | 3 `(1.28, 0.25, -50)` | `0.32*(v+50)/(1-exp(-(v+50)/4))` |
| m | beta | 3 `(1.4, -0.2, -23)` | `0.28*(v+23)/(exp((v+23)/5)-1)` |
| h (^1) | alpha | 2 `(0.128, -0.055556, -46)` | `0.128*exp(-(v+46)/18)` |
| h | beta | 4 `(4, -0.2, -23)` | `4/(1+exp(-(v+23)/5))` |
| n (^4) | alpha | 3 `(0.16, 0.2, -48)` | `0.032*(v+48)/(1-exp(-(v+48)/5))` |
| n | beta | 2 `(0.5, -0.025, -53)` | `0.5*exp(-(v+53)/40)` |

with type 3 = `A*k*(v-vh)/(1-exp(-k*(v-vh)))`, type 2 = `A*exp(k*(v-vh))`,
type 4 = `A/(1+exp(-k*(v-vh)))`. These are exactly the COBAHH rates of Brette
et al. (2007), Appendix, at `VT = -63` mV, and the default conductances
(0.1 and 0.03 S/cm2) match `genprop.set_defstr` in the `.ses` file.

`hhcell.hoc` line 2 is guarded so the same tree runs either way:

```hoc
if (name_declared("gmax_nahh") == 0) { load_file("hhchan.ses") }
```

With `x86_64/` built the compiled channels win; with it absent the original
ChannelBuilder path is used unchanged.

## Running it

```sh
nrnivmodl -coreneuron mechanisms     # builds libnrnmech.so and libcorenrnmech.so
sh verify_cn.sh                      # three arms, see below
```

`verify_cn.sh` runs three arms on one node: **A** NEURON CPU with the compiled
channels, **B** NEURON CPU with the original ChannelBuilder channels, **C**
CoreNEURON with the compiled channels. A vs B is the correctness check --
substituting the channels is only legitimate if it reproduces the original --
and A vs C is the CoreNEURON speedup.

Requires NEURON 9.x: the CoreNEURON engine is not shipped in the NEURON 8.0.2
pip wheel (`from neuron import coreneuron` imports, but running reports
`Could not find CoreNEURON library`). NEURON 9 also requires `Random123` for
`NetStim.noiseFromRandom`, so `common/ranstream.hoc` needs
`r.Random123(stream, 0, 0)` in place of `r.MCellRan4(...)`.

## Results

UMCS node inf03, 4000 cells, 5.0 s simulated, `dt = 0.05` ms. All arms are CPU
and single-threaded except the first, which runs on one A100:

| simulator | channels | wall (s) | spikes |
|-----------|----------|---------:|-------:|
| CoreNEURON 9.0.2, **GPU (A100)** | compiled NMODL | **27.0 ± 0.1** | 592,865 |
| GENESIS 2.5 (VAnet2) | tabulated | 46.9 ± 2.1 | 536,600 |
| CoreNEURON 9.0.2 | compiled NMODL | 76.5 ± 0.3 | 558,824 |
| NEURON 9.0.2 | compiled NMODL | 95.8 ± 0.2 | 558,824 |
| NEURON 9.0.2 | ChannelBuilder | 123.3 | 574,138 |
| NEURON 8.0.2 | ChannelBuilder | 76.5 | -- |

Mean ± std over three replicates for the top three rows; the ChannelBuilder rows
are single runs kept for reference. GENESIS 2.5 is **1.63 ± 0.07x faster than
CoreNEURON** and 2.04 ± 0.09x faster than NEURON 9.0.2 on the same node.
CoreNEURON is itself 1.25x faster than NEURON 9.0.2 CPU, which is the expected
order and indicates the CoreNEURON arm is working as designed rather than
misconfigured. Every NEURON and CoreNEURON replicate returned the same spike
count, so those arms are deterministic; the GENESIS spread (47.61, 44.51,
48.55 s) is the only meaningful source of uncertainty in the ratio.

### Why the comparison is fair

The two models are independent implementations of the Vogels-Abbott COBAHH
benchmark, so equivalence had to be established rather than assumed:

* **Size and connectivity.** Both are 4000 cells (3200 excitatory, 800
  inhibitory), single-compartment, with 80 synapses per cell -- GENESIS reports
  65 excitatory + 15 inhibitory per cell, and COBAHH builds 320\,000
  connections over 4000 cells.
* **Protocol.** Both drive the network externally for the first 50 ms only and
  then run on recurrent activity alone (`set_frequency 0` in VAnet2,
  `STOPSTIM = 50` in `common/netstim.hoc`).
* **Timestep and duration.** `dt = 0.05` ms and 5.0 s in both. VAnet2's batch
  script reaches 5.0 s as `tmax = 0.05` followed by `tmax = 4.95`; the
  `tmax = 2.0` in `dualexpVA-HHnet.g` belongs to the interactive script and is
  not what the benchmark runs. `common/init.hoc` needs `tstop = 5000` and
  `dt = 0.05`; the package defaults to `dt = 0.1`, which halves the work.
* **Activity.** Both networks settle into the same regime: 26.8 Hz mean rate in
  GENESIS (536\,600 spikes) against 27.9 Hz in NEURON (558\,824), a 4%
  difference. This matters because synaptic event handling scales with spike
  count, so a large rate gap would invalidate the wall-clock comparison.

  Measuring the GENESIS rate needs `spikecount.g`: `VAnet2-batch.g` records Vm
  from `middlecell`, `Redgecell` and `LLcell`, and the latter two sit on the
  edge and corner of the 2D grid. `planarconnect` makes connectivity
  distance-dependent, so those cells receive fewer inputs and fire at 7.6 and
  0.6 Hz against 15.8 Hz for the central cell -- estimating population activity
  from them understates it roughly threefold.

## CoreNEURON on the GPU

`coreneuron_gpu_standalone.sh`. CoreNEURON is built for accelerators, so leaving
it on CPU would have made this comparison flattering rather than informative.

Building CoreNEURON's OpenACC backend needs `nvc++`, and NEURON built with NVHPC
segfaults at startup here -- on a single passive soma, so it is not the model.
The way round it is to stop needing NEURON at run time. NEURON, on its working
pip (GCC) build, writes the model to disk; `special-core` then reads those files
and simulates on its own:

```
NEURON (pip, GCC) --nrncore_write--> model directory
                                            |
                            special-core --datpath ... --gpu
```

Two things had to be fixed to get there:

1. **The dump produced no files.** `init.hoc` runs the simulation itself and
   ends with `pc.done()`, so the process exits before `nrncore_write` is
   reached. The script patches a copy, commenting out `prun()`,
   `pc.runworker()`, `collect_results()`, `pc.done()` and `output_results()`.
   Five model files then appear.
2. **`special-core` would not load:** `undefined symbol: ...path14_M_split_cmptsEv`.
   Neither the system nor the gcc-toolset-13 `libstdc++.so.6` exports it, and
   `libstdc++fs` ships only as a static archive. Rebuild the mechanisms with
   `nrnivmodl -coreneuron -loadflags "-lstdc++fs"`.

Result: **27.0 ± 0.1 s** over three replicates (26.90 / 27.06 / 27.10 s), solver
time 26.40 / 26.59 / 26.64 s. Logs in `../logs/cn_gpu_r{1,2,3}.log`.

That the run is real, not an early exit, was checked in the output rather than
assumed: `Number of cells: 4000`, `Number of compartments: 12000`,
`--tstop=5000`, 426 MiB of GPU memory allocated, and our `khh.mod nahh.mod`
among the loaded mechanisms. The spike count is 592,865 against 558,824 on CPU,
a 6% difference -- the same activity regime, and comparable to the 4% between
GENESIS and NEURON that the fairness check above already accepts.

**This is 1.74x faster than GENESIS**, and it is reported as such in the paper.
GENESIS 2.5 cannot accelerate this benchmark at all: one spikegen per `hsolve`
turns a spiking network into one solver per cell, so dispatch dominates.

### What this does not show

CoreNEURON's multi-rank MPI configuration is still unmeasured, as is Arbor on a
spiking network. For the case where the GENESIS accelerator does apply, see the
multi-compartment comparison below.

## Multi-compartment comparison (2026-08-17)

The Vogels-Abbott comparison above runs on CPU on both sides, because that
network is spiking and the GENESIS accelerator declines it. For a paper about
GPU acceleration that leaves the central claim untested across simulators, so
the same three simulators were run on a model the accelerator does support:
N neurons, each a linear chain of 16 compartments, HH channels, current
injection, no synapses.

`hh_multicomp_neuron.py` and `hh_multicomp_arbor.py` reimplement
`hh_multicompartment_createmap.g` with matching geometry, passive properties,
conductances, injection and timestep. They are throughput benchmarks: the
per-compartment per-step arithmetic matches, but no claim is made that the
three produce identical voltages.

N=10000 (160,000 compartments), K=5000 steps, all on inf03 (Xeon Platinum 8358,
A100), mean of 3:

| simulator | backend | wall (s) |
|---|---|---:|
| GENESIS 2.5 | **GPU** | **1.75 ± 0.08** |
| CoreNEURON 9.0.2 | CPU | 60.94 ± 0.15 |
| NEURON 9.0.2 | CPU | 82.82 ± 2.00 |
| GENESIS 2.5 | CPU | 123.41 ± 1.75 |

Two things worth stating plainly. On CPU the GENESIS solver is 2.02x slower
than CoreNEURON. The accelerator gives 70.5x end-to-end over the same code on
the same node, which is a like-for-like measurement, and lands GENESIS 34.8x
ahead of the fastest CPU competitor -- but that last figure compares a GPU
against a CPU and must be labelled as such, not presented as a simulator-to-
simulator result.

### Two silent-fallback traps

**CoreNEURON only takes over for cells registered with `ParallelContext` under a
gid.** Without that it leaves the run on NEURON's own solver, reports nothing,
and the only symptom is that the timings match the plain arm exactly (83.6 s
against 81.9 s here). `bench_multicomp_cross.sh` now greps the output for
CoreNEURON's own `nrn_setup` line and warns when an arm did not engage.

**The nodes have different CPUs** -- inf02 is a Xeon Gold 6342 at 2.80 GHz,
inf03 a Xeon Platinum 8358 at 2.60 GHz. Single-threaded arms measured on
different nodes are not comparable; every figure above is from inf03.

### Are the three the same model? (2026-08-18)

`vm_cross_check.sh` records Vm from one cell in all three simulators, at the
soma and at the centre of the last dendrite, and `paper/scripts/compare_vm_traces.py`
compares them. Two invariants are used, because the cell fires repetitively and
a point-by-point comparison of a 200 ms run would measure phase drift: the
first action potential, and the firing rate.

It found three defects, all in the harness rather than in any simulator:

| # | defect | effect |
|---|---|---|
| 1 | Arbor injected at `(location 0 0.5)` | an unbranched cell is one 770 um branch, so that is 385 um from the root -- mid-dendrite, not the soma |
| 2 | Arbor used `neuron_cable_properties()` defaults | ENa +50 / EK -77 instead of the model's +45 / -82; Arbor fired at 65 Hz against NEURON's 10 |
| 3 | GENESIS scaled every `Gbar` by `soma_area` | each dendrite carried 4x the intended channel density (`soma_area/dend_area` = 4); `Rm`, `Cm`, `Ra` always used the right area |

After the fixes NEURON and Arbor agree to 0.02 mV at the action-potential peak,
1.6 mV across the spike once the peaks are aligned, and 0.01% on firing rate.
GENESIS peaks 4.6 mV lower and 0.24 ms earlier and fires faster, because its
Hodgkin-Huxley rates are written about EREST = -70 mV where NEURON's `hh` is
written about -65 mV: GENESIS's `alpha_m(v)` is NEURON's `alpha_m(v+5)`,
verified numerically. That is a parameterisation convention, not a defect, and
it is left alone.

**Does the rate difference invalidate the throughput comparison?** No, and
`rate_vs_walltime.sh` measures it rather than arguing it. The model has no
synapses and no events, so a spike costs nothing beyond the channel update
every compartment performs every step. Running each simulator with the
injection switched off:

| simulator | driven | quiescent |
|---|---:|---:|
| GENESIS 2.5 GPU | 1.629 s | 1.656 s |
| Arbor 0.10.0 GPU | 1.558 s | 1.560 s |
| NEURON 9.0.2 CPU | 85.438 s | 84.927 s |

Re-running the full six-point sweep after the fixes moved no wall time by more
than 1.3%, so none of the published timings depended on the defects.

GENESIS's own two backends agree to 2.6e-5 V over 200 ms and 14 spikes, fp32
against fp64, with an identical spike count -- the phase drift the paper
describes for long runs, not a disagreement.

### GPU-to-GPU

Both sides now run on the A100. Arbor 0.10.0 builds against CUDA directly rather
than through OpenACC (`arbor.config()["gpu"] == "cuda"`) and needed no special
handling; the model is `hh_multicomp_arbor.py`. CoreNEURON's GPU path took the
standalone workaround described above.

---

Prepared by Karol Chlasta (karol@chlasta.pl).
