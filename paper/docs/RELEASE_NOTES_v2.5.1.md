# GENESIS 2.5.1

The release the SoftwareX manuscript describes. v2.5 archived the accelerator
before the spiking-network work and before three defects in it were found, so
that archive no longer matches the paper.

## The accelerator now runs a synaptically coupled spiking network

`hsolve` tracked one spike generator per solver, which forced such a network to
be built as one solver per cell. It now tracks one per compartment, so a whole
layer is a single solver: 1.41x faster on the CPU alone, and the device
computes the network for the first time -- at parity with its own CPU arm,
reproducing its spike count to 1.05%.

Three defects in the accelerator as first released had to be fixed to get
there, each of which returned wrong voltages rather than an error:

- `SYN2_OP` dropped the synaptic current; with two synaptic channels per cell,
  breaking out of the opcode loop dropped the second
- the host uploaded the whole `chip[]` array every step, erasing the kernel's
  own synaptic and gating state
- the device solve omitted the Crank-Nicholson correction, which cost 85% of
  the spikes

## Also in this release

- `getenv` on an unset variable returned NULL, so every optional environment
  variable printed `** Error - CastToStr: NULL string` in a run that had
  worked. Unset now reads as an empty string.
- `reproduce/` gained a stage for the spiking network, an architecture guard
  that refuses to time a binary carrying no code for the card in the machine,
  and an Arbor arm in the crossover sweep.
- The Vogels-Abbott scripts can record every spike, off by default, through
  `GENESIS_VANET2_SPIKEFILE`.

## Verification

`|CPU - CUDA| = 7.04e-08 V`, PARITY: PASS, on both an A40 (sm_86) and an A100
(sm_80). `sh reproduce/run_all.sh` re-measures the paper's claims and prints
each published value beside the reader's own.
