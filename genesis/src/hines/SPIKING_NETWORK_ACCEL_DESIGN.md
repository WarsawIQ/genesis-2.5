# Accelerating synaptically coupled spiking networks

**Status:** implemented 2026-08-19, with one of two obstacles cleared.

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
