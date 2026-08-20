# Accelerating synaptically coupled spiking networks

**Status:** implemented. The accelerator runs a synaptically coupled spiking network correctly, and beats the CPU arm above about 5000 cells.

The spike-generator limit is gone and the Vogels--Abbott model now builds as
one solver per layer, which is **1.55x faster on CPU** (31.8 +/- 0.4 s against
49.3 +/- 2.2 s, three replicates each on inf02). The accelerator still cannot
run it: the device's synaptic-channel opcode does not reproduce the CPU
result, and SYN2_OP compartments are therefore refused at SETUP and computed
on the CPU. See *What measuring it found* at the end.
**Companion to:** `GPU_HINES_SOLVE_DESIGN.md`, which covers the tree-elimination kernel.

## The problem, stated correctly

GENESIS 2.5 declines to accelerate spiking networks. The reason recorded in the
SoftwareX draft — that dispatch must be batched across `hsolve` elements, and
that batching collides with event ordering — is **wrong**, and this document
supersedes it.

The real constraint is one line of policy. `hines_child.c` refuses a second
spike generator in one solver:

```c
if (firstSPIKE) {
    firstSPIKE=0;
} else {
    Error();
    printf(" during SETUP of %s: second spikegen %s not allowed.\n", ...);
    return(ERR);
}
```

`hsolve->spikegen` is a single `Element *`, and `h_dospike_event()` walks that
one element's outgoing message list. One spikegen per solver means one cell per
solver for any spiking model, so VAnet2 builds 4000 solvers and pays 4000
dispatches per step. That is what makes the accelerator pointless here, not
anything about batching.

Batching is not needed and would not help. VAnet2 sets `prop_delay = 0.0` —
the published benchmark uses no axonal delay — so the min-delay window that
NEST, CoreNEURON and Arbor batch over is one step wide. With many cells in one
solver there is one dispatch per step already, and the existing per-step path
delivers events correctly between steps.

## What already works

Per-step dispatch supports spiking models on the GPU today **under CUDA**. The
CUDA kernel implements `SPIKE_OP` and `SYN2_OP`; the OpenCL one does not (see
*Backends* below). The division of labour the element system forces:

| stage | where | why |
|---|---|---|
| threshold crossing | device | `spike_flag[compartment]`, refractory counter in a writable buffer because `ops[]` is read-only on the device |
| event emission | host | `h_dospike_event()` uses GENESIS messaging, which the device has no access to |
| synaptic activation | host, before dispatch | `h_dosynchan()` calls into the `Synchan` element to fetch activation into `chip[]` |
| synaptic conductance | device | the dual-exponential X/Y update, mirroring `hines_chip.c` |

The device side is already indexed **per compartment** (`spike_flag[gid]`,
`refrac0[c]` in `build_comp_index`). It needs no change for this work.

## What the profile says this can buy

`perf` on VAnet2, 4000 cells, 5 s, inf03, CPU build (48.4 s wall):

| share | symbol group | fate |
|---:|---|---|
| 58.9% | `do_chip_hh4_update`, `HinesSolver`, `do_crank_hsolve` | the accelerator replaces this |
| 15.9% | element/messaging dispatch | stays on the host |
| 14.7% | `Synchan`, `h_dosynchan` | stays on the host |
| 4.1% | scheduler loop | stays |
| 4.0% | external-drive RNG | stays |

Amdahl ceiling **2.43×**, floor **19.3 s** against the measured 46.9 s. With
per-step launch and transfer over 100,000 steps the realistic target is
**22–25 s**. CoreNEURON on the same A100 does this network in 27.0 s.

This design does **not** accelerate synapses. `h_dosynchan()` fires only when a
synaptic event is due, not every step, so its cost tracks network activity; it
and the messaging under it are the ~30% that sets the ceiling. Moving them to
the device is a separate, larger project — it would raise the ceiling to about
9× — and is out of scope here.

## Design

### Spikegen identity

Replace the single pointer with a per-compartment table.

```c
/* hines_struct.h */
Element **spikegens;   /* [ncompts], NULL where the compartment has none */
int       nspikegens;
```

`h_dospike_event(hsolve)` becomes `h_dospike_event(hsolve, comp)` and walks
`hsolve->spikegens[comp]`.

The interpreter already knows the compartment: it advances `vm` once per
compartment at the top of the loop, so the index is `(int)(vm - hsolve->vm) - 1`
with no counter to maintain and nothing added to the hot path.

**Rejected alternatives.** An ordinal counter over `SPIKE_OP` occurrences is
cheaper still, but it assumes the interpreter always walks the whole stream in
order; a future early exit would misroute spikes silently. Widening `SPIKE_OP`
with an index operand is the most explicit option and the most dangerous: it
changes the opcode stream layout, so every downstream `ops[]` and `chip[]`
offset moves, including `build_comp_index` in both backends. A previous attempt
at this problem changed CPU results (VAnet2 output md5 `1440eb86` →
`0b663c0c`) and was reverted. Keeping the stream layout untouched is the point
of this design.

### Setup

`hines_child.c` drops the refusal and records each spikegen against the
compartment it belongs to. The allocation is `ncompts` pointers, dense for a
spiking network and empty for models without spike elements.

### Backends

`cuda_backend.cu` currently counts how many compartments crossed threshold and
`cuda_hsolve.c` calls `h_dospike_event()` that many times. That is only correct
because there is one spikegen. It becomes a walk over the flag array, emitting
from `spikegens[i]` for each flagged compartment `i`. No kernel changes.

**CUDA only.** The OpenCL kernel does not implement `SPIKE_OP` or the synaptic
opcodes at all: `ocl_hsolve.c` marks any compartment carrying them `cpu_only`
and then disables acceleration for the whole solver. Reaching parity there
means writing those opcodes into `ocl_channel.cl` first, which is a separate
piece of work and is not part of this design. Until it is done, a spiking
network accelerates under CUDA and falls back to the CPU under OpenCL, which is
the behaviour that already exists — this change does not make it worse.

### Model

VAnet2 builds one solver per cell (`create hsolve solver` … `call solver
DUPLICATE`, `path "../soma"`). A new `VAnet2-batch-1solver.g` builds one solver
across all somas instead. **The existing script is left untouched**: it is the
one that produced the published 46.9 s, and that number has to stay
reproducible.

## Validation

In this order. Gate 1 is unconditional — nothing downstream is worth measuring
until it passes.

1. **The change is a no-op on unmodified models.** Every model with at most one
   spikegen per solver, VAnet2 included, must produce byte-identical output.
   VAnet2's output md5 must remain `1440eb86`. If it moves, revert rather than
   explain.
2. **One solver against many, on CPU.** The one-solver variant will not be
   bit-identical to the original — different solver grouping changes the
   arithmetic order — so the criterion is agreement of regime: firing rate
   within the tolerance already accepted between GENESIS and NEURON (4%).
3. **GPU against CPU on the one-solver variant.** The fidelity standard the
   paper already uses for spiking runs: same spike count, phase drift only.
4. **Timing**, once 1–3 pass, on an idle node, against the 46.9 s baseline and
   CoreNEURON's 27.0 s.

## Risks

- **Silent misrouting.** A spike emitted from the wrong spikegen changes network
  dynamics without any error. Gate 2 catches gross cases; a targeted test with
  two cells and asymmetric connectivity catches the rest and should be written
  first.
- **Memory.** `ncompts` pointers per solver is negligible for VAnet2 and
  proportional for large models; allocate only when the model has a spikegen.
- **The 4000-solver path must keep working.** Existing scripts using the
  `DUPLICATE` idiom must be unaffected, which gate 1 covers.
- **Gate 1 has a harness already.** `cluster_bringup/80_accel_regression.sh`
  records VAnet2's `Vm_out_1000.txt` md5 into a golden file and diffs against
  it. Gate 1 is `record` before the change and `check` after, on the same
  device -- the script refuses to compare across devices because the fp32
  kernels are not bit-identical between them.
- **Host cost may dominate sooner than expected.** If per-step launch overhead
  over 100,000 steps is worse than estimated, the result lands above 27 s and
  the honest outcome is a measured negative. The paper's framing changes either
  way, because the recorded diagnosis is wrong regardless of the timing.


---

## What measuring it found

Three defects, all in released code, all invisible while every solver holds one
identical cell.

**1. The device's synaptic path returns wrong results.** Two compartments, one
synchan, one spike generator, driven by injected current: two spikes on the
CPU, none under CUDA, with the accelerator reporting ready and raising no
error (`genesis/Scripts/benchmark/spikegen_syn_check.g`). Remove the synchan
and both arms give two spikes (`spikegen_gpu_check.g`), so the spike path is
sound and the synaptic one is not. SYN2_OP compartments are now marked
`cpu_only`, which is what the SETUP guard was documented to do and did not.
Repairing the device path is the next piece of work; until then a
synaptically coupled network runs on the CPU.

**2. The synaptic site list was per process, not per solver.** `syn_sites` and
`syn_nsites` were file-scope statics capped at 4096 entries, with the excess
dropped in silence -- the opposite of the comment above them. With one solver
per cell every list coincides, so reading another solver's list returns the
right answers; two solvers of different sizes do not. Now stored per solver
and sized from the model.

**3. The legacy `spikegen` field cannot be guarded.** Assigning it only when
NULL turns "last generator seen wins" into "first wins" and moves VAnet2's
output. It is assigned exactly as before; the per-compartment table is
additive.

## What the measurement cost, and what it is worth

The profile predicted 22-25 s for a GPU arm. That prediction cannot be tested
until defect 1 is repaired. What can be said now is that the restructuring the
spikegen change enables is worth 1.55x on its own, and that per-step dispatch
costs about 58 us per call against 8.5 us of kernel time at this size -- so
even a correct synaptic path would have to overcome that before the GPU pays
on a 4000-cell network.

Note on validating any of this: VAnet2's recorded md5 differs between machines,
because the network is chaotic and the compilers round differently. Gate 1 is
only meaningful on the node the golden was recorded on. A local build gives
`1d6e247b` where the A40 gives `1440eb86`, and neither is wrong.


## Narrowing defect 1: what is ruled out

Reproducer: `genesis/Scripts/benchmark/spikegen_syn_check.g`, two compartments,
one synchan, run under both binaries. `GENESIS_CUDA_ALLOW_SYN=1` re-enables the
device path so it can be observed; `GENESIS_CUDA_SYNDEBUG=1` prints the indices.

Ruled out by measurement, in this order:

| hypothesis | result |
|---|---|
| the host synaptic pass never runs | no: `sntab=1`, `needs_chip_every_step=1` |
| the opcode stream desynchronises | no: `op_i += 3` matches `hines_chip.c` |
| the chip slots desynchronise | no: `chip_i += 2` matches |
| the host decays the wrong chip slot | no: stream `chip_i=11`, host `childchips[4]=11` |
| the spike path itself is broken | no: without the synchan both arms give two spikes |

What remains is how the synaptic conductance enters the membrane current. The
device accumulates in `ADD_CURR_OP` as `sumgchan += Gk; ichan += Ek*Gk`, while
the chanmode-4 CPU path computes `Gk*(Ek-Vm)` into `givals`. Those are not the
same route, and the symptom fits: over 20,000 steps the CPU cell fires twice
and returns to rest (-71.5 mV) while the device cell sits depolarised at
-9.2 mV and never reaches the 0 mV threshold. A synaptic current entering
without its voltage-dependent term, or with the wrong sign, would look exactly
like that.

The two arms track each other closely for the first hundred steps
(2.5e-9 V at one step, 8.6e-8 at ten, 8.3e-5 at a hundred), so this is not a
gross indexing error appearing immediately; it is a systematic bias that grows
as the synaptic conductance becomes significant.

Until it is fixed, `SYN2_OP` compartments are marked `cpu_only` and the solver
runs on the CPU.


## One defect fixed, the model still wrong

`hines_chip.c` does not fall through after `SYN2_OP`. It jumps to `DOADDCURR`,
accumulates `sumgchan += Gk; ichan += Ek*Gk`, and **breaks out of the
compartment's opcode loop**: a synaptic channel carries its own ADD_CURR and
nothing follows it in the stream. Both device kernels instead did `continue`,
so the synaptic conductance was computed and discarded, and the thread went on
reading opcodes the CPU had already stopped at. That is a real defect and it is
fixed.

It is not the whole story: with it fixed the two-compartment model still gives
two spikes on the CPU and none on the device.

Also ruled out since: **compartment ordering**. Two cells driven asymmetrically
with no synapse anywhere agree between CPU and device to 3e-7 V on both cells
(`spikegen_asym_check.g`), so the kernel's per-thread compartment mapping is
sound and the earlier suspicion -- that identical cells had been hiding a
swap -- is wrong.

What is left to check, in order: whether the device's `ichan`/`sumgchan`
accounting reproduces the chanmode-4 CPU path, which also maintains `Im` and
the per-channel `givals` array and may not be equivalent to accumulating
`Ek*Gk` alone; and whether the host's decay in `cuda_synaptic_pass` is applied
at the same point in the step as the interpreter's, given the interpreter
decays inside the stream while the host does it before the dispatch.

The refusal stays in place: `SYN2_OP` compartments are `cpu_only` unless
`GENESIS_CUDA_ALLOW_SYN=1`, which exists only to observe the defect.


## The chip overwrite, and what it did not fix

For a model with synapses `needs_chip_every_step` is true, and the host then
uploaded the **whole** `chip[]` array before every dispatch. Only `results`
came back. So each step overwrote everything the kernel had written the step
before -- the synaptic Y state and, because they live in the same array, every
channel's gating variables. The cell's channels were frozen at their initial
values, which is why it drifted to -9 mV and never fired.

`cuda_backend_download_chip()` reads the array back after each dispatch when
the host writes into it. With that in place the two-compartment synaptic model
gives two spikes on both arms and Vm agrees to 2e-7 V, with CUDA engaged.

**The network still fails.** Vogels-Abbott as one solver per layer: 545,371
spikes on the CPU, none on the device. Something that model has and the
two-compartment one does not is still wrong. Candidates not yet tested, in the
order worth trying: two solvers of different sizes in one process rather than
one; 80 synapses per cell against one; a `Randomspike` external drive; and
`SYN3_OP`, which a synchan with a non-zero frequency emits and the kernel does
not implement at all.

The refusal therefore stays. The download is kept because it is necessary and
verified, but shipping an accelerator that is right on two compartments and
silently wrong on a network is worse than shipping one that declines both.

Cost note: the download is not free. VAnet2's GPU arm went from 43 s to 74 s
with it, on an array of 64,000 doubles fetched 100,000 times. If the network
case is fixed, the right form is almost certainly to write back only the slots
the host touches rather than the whole array.


## Outcome

Vogels--Abbott, 4000 cells, one solver per layer, A40, three replicates:

| arm | wall | spikes |
|---|---:|---:|
| stock, 4000 solvers, CPU | 49.3 +/- 2.2 s | 536,600 |
| one solver per layer, CPU | **31.5 +/- 0.4 s** | 545,371 |
| one solver per layer, GPU | 41.1 +/- 1.6 s | 547,271 |

Correctness holds: 0.35% on spike count between the device and its own CPU arm,
against the 4% this work already accepts between simulators.

> Superseded 2026-08-20. Once the dispatch came down from 88.7 s to 34.5 s the
> device count moved to 551,117, so the agreement is 1.05%, not 0.35%. The
> network is chaotic and fp32 diverges at a rate set by the order of
> operations, which the reduced dispatch changed. Both counts are identical on
> the A40 and the A100 -- one thread per tree, no cross-thread reduction -- and
> the CPU arm is 545,371 on both. See
> `cluster_bringup/logs/spiking_accel/spike_agreement_20260820.txt`.

Two wins and one open problem. Lifting the spikegen limit is worth **1.56x on
CPU alone**, from no longer building four thousand solvers. The device now
computes the network, which it never did before. But the GPU arm is 1.30x
slower than the CPU one, because a network with zero axonal delay cannot batch
and every one of the 100,000 steps pays a dispatch: two solvers, two kernel
launches each, and a Vm readback.

Reductions worth trying, in order: fold the scatter into the main launch,
batch the Vm readback, and give each solver its own stream so the two do not
serialise. The profile's 2.4x ceiling is still there to be reached; nothing
about it is blocked by correctness any more.


## Where it pays

The per-dispatch cost is fixed; the CPU's work grows with the population. So
the question is not whether the accelerator helps but above what size.
Vogels--Abbott through the layer-size knob, A40, one run per point:

| cells | CPU | GPU | |
|---:|---:|---:|---|
| 4,000 | 31.5 s | 34.5 s | CPU by 9% |
| 5,120 | 49.7 s | 49.6 s | even |
| 12,500 | 124.1 s | 82.1 s | **GPU by 1.51x** |
| 24,500 | 286.0 s | 205.6 s | **GPU by 1.39x** |

The published benchmark sits just below the crossing, which is why measuring
only there made the accelerator look like a loss.

Getting from 2.68x slower to the crossing took three changes, in order of what
they were worth: sending only the synaptic X slots instead of the whole chip
array each step (88.7 -> 41.1 s), finishing the single-compartment solve in the
channel kernel so vm[] never leaves the device (41.1 -> 34.5 s), and making
per-dispatch kernel timing opt-in (no measurable effect, kept because
instrumentation should not be a default cost).

What is left, if the crossing is worth moving further down: fold the scatter
into the channel launch, and give each solver its own stream so the two layers
do not serialise.
