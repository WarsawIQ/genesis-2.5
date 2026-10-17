# Vogels-Abbott in Arbor

The fourth implementation of the benchmark, after GENESIS, NEURON and
CoreNEURON. It exists so the spiking comparison can be GPU-to-GPU rather than
stopping at CoreNEURON, which is the last gap Reviewer 2 pointed at.

## What works

`arbor-build-catalogue` compiles the same NMODL channels the CoreNEURON arm
uses into an Arbor catalogue, with CUDA:

    arbor-build-catalogue cobahh mech --gpu cuda

Two edits were needed against the CoreNEURON copies, both in `mech/`: Arbor's
modcc rejects `v` and the USEION variables (`ena`, `ina`, `ek`, `ik`) inside
`ASSIGNED`, where NEURON accepts them. The kinetics are untouched, so these are
the channels already validated byte-for-byte against NEURON's ChannelBuilder
originals.

The model builds and runs. At the benchmark's size it reports the right
structure: 4000 cells, 3200 excitatory, 800 inhibitory, fan-in 80.

## Firing rate: resolved on 2026-08-20 (ce8e432)

The first version fired at 43-45 Hz against the benchmark's 27.3 Hz. It drew
connectivity as 2% of the whole population; `net.hoc` draws exactly
C_E = int(N_E * 0.02) excitatory and C_I = int(N_I * 0.02) inhibitory inputs per
cell. Both give a mean in-degree of 64 + 16, but the binomial spread let some cells
receive less inhibition, and those carried the population rate up. Drawing per
population gives 30.1 Hz: 602,720 spikes in 5 s, the same count in every
replicate (`replicates_A100.txt`), in the regime of CoreNEURON (29.6 Hz) and
GENESIS (27.3 Hz). Checked on the way and found right: the drive stops at 50 ms,
the detector does not double-count (shortest interval 2.38 ms), `expsyn` takes
the `e` parameter, and the excitatory/inhibitory gid split matches `net.hoc`.

## Wall time

On the A100 the 5 s run takes about 150 s (`replicates_A100.txt`; the revision
campaign's E1 measured 150.0 ± 1.8 s). Arbor advances in epochs of half the
smallest connection delay and exchanges spikes once per epoch
(https://docs.arbor-sim.org/en/stable/concepts/interconnectivity.html). With the
one-step delay described below, an epoch is half a time step, so spikes are
exchanged at least once per step. We have not profiled Arbor to confirm that this
is where its time goes. The CPU build of this arm was never tuned (85 s for
200 ms, probably the thread count in `A.context()`), and no CPU number from it is
used.

## The one deliberate departure from the benchmark

The benchmark specifies zero axonal delay. Arbor cannot express it: the
scheduler advances in min-delay epochs, so a connection delay must be positive.
This arm uses one timestep, 0.05 ms. With a zero delay Arbor accepts the model
and then advances no time at all -- the symptom is a run that returns in a
millisecond having produced no spikes.

## Status

Validated as above. The GPU arm is the Arbor row of the cross-simulator table
(E1, `cluster_bringup/campaign/E1_cross_simulator.sh`, which refuses a run whose
spike count is more than 20% away from 602,720).
