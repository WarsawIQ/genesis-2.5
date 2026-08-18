# Accelerating synaptically coupled spiking networks

**Status:** design, 2026-08-19. Not implemented.
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
