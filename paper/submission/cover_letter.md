Dear Editors,

We are resubmitting *GENESIS 2.5: optimisation and opt-in OpenCL/CUDA
acceleration for the GENESIS/PGENESIS compartmental neural simulator*,
previously handled as SOFTX-D-26-00952.

The earlier decision turned on the absence of a head-to-head comparison with
other simulators and on questions about the benchmarking methodology. Rather
than argue the point, we went and did the measurements. The paper is
substantially different as a result.

**Head-to-head, on two models, on CPU and GPU.** GENESIS 2.5 is now compared
with NEURON, CoreNEURON and Arbor on the published Vogels-Abbott COBAHH
network, and with NEURON and Arbor on a 160,000-compartment multi-compartment
population. The competitors' GPU backends are included: CoreNEURON through
its OpenACC path and Arbor through CUDA. We say why those three and not
NEST or Brian 2 -- they simulate point-neuron networks rather than dendritic
morphologies, so they would not be running the same computation.

**Equivalence verified rather than assumed.** Independent implementations of
the same published benchmark differ. We compared recorded membrane potentials
across the three simulators before comparing their wall times, and report
where they disagree and why. Setting that up exposed three errors in our own
harness, which we corrected and disclose.

**One timing definition throughout.** Every ratio in the paper wall-clocks
both arms around the whole process, construction and transfers included. We
state this explicitly because timing the two arms by different clocks inflates
speedups roughly tenfold, and we report the step-phase figures separately
rather than quoting them as what a user gets.

**Results that do not favour us are in the paper.** CoreNEURON on an A100 runs
the spiking benchmark 1.23x faster than our best arm. The accelerator now runs
a synaptically coupled spiking network -- new in this release -- but only at
parity with its own CPU arm, and we explain why: a zero-delay network cannot
batch dispatches. Neither our simulator nor Arbor is faster in general; their
lines cross, and where they cross depends on the card, which we measured on
two.

**A reproduction pack.** `sh reproduce/run_all.sh` rebuilds the software,
re-measures the claims on the reader's own hardware, regenerates the figures
from those measurements, and prints each published value beside theirs with a
verdict. It refuses to time a binary built for a different GPU than the one in
the machine -- a failure that cost us a day and would otherwise cost a
reviewer one.

**On the Code Ocean capsule.** The submission form asks for one. We have not
made a capsule, and we would rather explain why than leave the field empty.
What this paper claims is GPU acceleration, and a capsule without an NVIDIA
card would exercise only the CPU paths -- demonstrating nothing that is in
dispute, and possibly suggesting the results cannot be reproduced. In its
place we offer the repository, an archived release whose DOI names the exact
version every number was measured on, and the reproduction pack described
above, which runs on the reviewer's own hardware rather than on a machine we
chose. If the editors would still like a capsule, we can prepare one for the
two claims that need no GPU: model construction reduced from O(n^2) to linear,
and the 1.41x gained on the CPU by building a spiking network as one solver
per layer.

The software is archived at https://doi.org/10.5281/zenodo.22032886, which is
the exact version the measurements were taken on.

We hope the revised manuscript now meets the standard the reviewers asked for.

Yours sincerely,

Karol Chlasta (corresponding author)
Grzegorz Marcin Wojcik
