# Vogels-Abbott in Arbor — built, not yet validated

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

## What does not yet match, and must before any timing is quoted

**Firing rate.** 42.9 Hz against the benchmark's 27.3. The network is in the
right kind of regime -- self-sustaining, not silent -- but not the same one.
Candidates not yet worked through: the external drive, where netstim.hoc gives
its NetCon `delay = 1` and a weight this file has not yet traced, and the
shutdown NetCon at netstim.hoc:70 (`weight = -1`) which stops the stimulus and
has no equivalent here yet.

**Wall time.** 85 s for 200 ms on CPU, which extrapolates to about 35 minutes
for the 5 s run -- roughly twenty times NEURON's 95.8 s for the same work. That
is not a plausible figure for Arbor and points at this harness's configuration,
most likely the thread count in `A.context()`, rather than at the simulator.

## The one deliberate departure from the benchmark

The benchmark specifies zero axonal delay. Arbor cannot express it: the
scheduler advances in min-delay epochs, so a connection delay must be positive.
This arm uses one timestep, 0.05 ms. With a zero delay Arbor accepts the model
and then advances no time at all -- the symptom is a run that returns in a
millisecond having produced no spikes.

## Status

Do not put a number from this arm in the paper until the rate matches. The
multi-compartment comparison earned its place by having its equivalence
measured rather than argued, and this one has not yet.
