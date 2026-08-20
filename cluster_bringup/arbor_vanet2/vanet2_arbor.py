#!/usr/bin/env python3
"""The Vogels-Abbott COBAHH benchmark, rebuilt in Arbor.

Fourth implementation of this network, after GENESIS (Scripts/VAnet2), NEURON
(ModelDB 83319) and CoreNEURON. Arbor is the one competitor whose GPU backend
is reachable on this cluster, so this is what makes the spiking comparison
GPU-to-GPU rather than stopping at CoreNEURON.

Parameters are taken from the same source the other arms use, the Destexhe
benchmark's cobahh/hhcell.hoc and common/net.hoc:

    soma        L = diam = 79.7885 um  (area 20,000 um^2), one compartment
    cm          1 uF/cm2
    pas         g = 5e-5 S/cm2, e = -65 mV
    nahh        gmax 0.1 S/cm2,  ena  +50 mV
    khh         gmax 0.03 S/cm2, ek   -90 mV
    excitatory  ExpSyn tau 5 ms,  e   0 mV,  weight 0.006 uS
    inhibitory  ExpSyn tau 10 ms, e -80 mV,  weight 0.067 uS
    connectivity 2%, delay 0, 80% excitatory
    dt 0.05 ms, 5 s

The channels are the NMODL transcriptions already validated against NEURON's
ChannelBuilder originals, compiled into an Arbor catalogue -- Arbor's built-in
hh is the classic 1952 kinetics, not the Traub-Miles variant this benchmark
uses, so using it would have compared a different cell.

Env:
    ARBOR_COBAHH_CAT   path to cobahh-catalogue.so (required)
    NCELL              total cells (default 4000)
    USE_GPU=1          run on the GPU
    TSTOP_MS           default 5000
    SEED               default 42

Prepared by Karol Chlasta (karol@chlasta.pl).
"""

import os
import random
import sys
import time

import arbor as A
from arbor import units as U

NCELL = int(os.environ.get("NCELL", "4000"))
USE_GPU = os.environ.get("USE_GPU", "0") == "1"
TSTOP = float(os.environ.get("TSTOP_MS", "5000"))
SEED = int(os.environ.get("SEED", "42"))
DT = 0.05
CAT = os.environ.get("ARBOR_COBAHH_CAT", "")

N_I = int(NCELL / 5.0)          # net.hoc: N_I = int(ncell/5.0)
N_E = NCELL - N_I
CONNECTIVITY = 0.02
AMPA_GMAX = 0.006               # uS
GABA_GMAX = 0.067               # uS
# The benchmark specifies zero axonal delay. Arbor cannot express that: its
# scheduler advances in min-delay epochs, so a connection delay has to be
# positive. One timestep is the smallest value that keeps the model as close to
# the specification as the simulator allows, and it is what the Arbor arm uses.
DELAY = DT
THRESHOLD = 10.0                # NEURON NetCon default

# 20,000 um^2 as a single compartment, the same geometry hhcell.hoc builds
DIAM = 79.7885


def make_cell():
    tree = A.segment_tree()
    tree.append(A.mnpos,
                A.mpoint(0, 0, 0, DIAM / 2),
                A.mpoint(DIAM, 0, 0, DIAM / 2),
                tag=1)
    decor = (
        A.decor()
        .set_property(Vm=-65.0 * U.mV, cm=0.01 * U.F / U.m2)
        .set_ion("na", rev_pot=50.0 * U.mV)
        .set_ion("k", rev_pot=-90.0 * U.mV)
        .paint('(all)', A.density("pas/e=-65", {"g": 5e-5}))
        .paint('(all)', A.density("nahh", {"gmax": 0.1}))
        .paint('(all)', A.density("khh", {"gmax": 0.03}))
        # one synapse of each kind per cell, as hhcell.hoc's synlist does
        .place('(location 0 0.5)', A.synapse("expsyn", {"tau": 5.0, "e": 0.0}), "exc")
        .place('(location 0 0.5)', A.synapse("expsyn", {"tau": 10.0, "e": -80.0}), "inh")
        .place('(location 0 0.5)', A.threshold_detector(THRESHOLD * U.mV), "det")
        .discretization(A.cv_policy_every_segment())
    )
    return A.cable_cell(A.morphology(tree), decor)


class VogelsAbbott(A.recipe):
    def __init__(self):
        A.recipe.__init__(self)
        self.cell = make_cell()
        self.props = A.neuron_cable_properties()
        if CAT:
            self.props.catalogue.extend(A.load_catalogue(CAT), "")
        # Connections drawn once, so the network is fixed for the run and the
        # same for both backends.
        rng = random.Random(SEED)
        self.conns = []
        for gid in range(NCELL):
            srcs = rng.sample(range(NCELL), int(CONNECTIVITY * NCELL))
            self.conns.append(srcs)

    def num_cells(self):
        return NCELL

    def cell_kind(self, gid):
        return A.cell_kind.cable

    def cell_description(self, gid):
        return self.cell

    def global_properties(self, kind):
        return self.props

    def connections_on(self, gid):
        out = []
        for src in self.conns[gid]:
            if src == gid:
                continue
            # the first N_E gids are excitatory, as in net.hoc
            if src < N_E:
                out.append(A.connection((src, "det"), "exc",
                                        AMPA_GMAX, DELAY * U.ms))
            else:
                out.append(A.connection((src, "det"), "inh",
                                        GABA_GMAX, DELAY * U.ms))
        return out

    def event_generators(self, gid):
        # The benchmark drives the network externally for the first 50 ms and
        # then lets it run on its own recurrent activity.
        # netstim.hoc drives ncell/50 cells with a mean interval of 70 ms and
        # shuts off at 50 ms; the rest of the network is driven only by them.
        if gid >= NCELL // 50:
            return []
        return [A.event_generator(
            "exc", AMPA_GMAX,
            A.poisson_schedule(tstart=0.0 * U.ms, freq=(1000.0 / 70.0) * U.Hz,
                               seed=gid + SEED, tstop=50.0 * U.ms))]

    def probes(self, gid):
        return []


def main():
    if not CAT:
        sys.exit("ARBOR_COBAHH_CAT must point at cobahh-catalogue.so")

    build_t0 = time.time()
    recipe = VogelsAbbott()
    ctx = A.context(gpu_id=0) if USE_GPU else A.context()
    decomp = A.partition_load_balance(recipe, ctx)
    sim = A.simulation(recipe, ctx, decomp)
    sim.record(A.spike_recording.all)
    build_t = time.time() - build_t0

    run_t0 = time.time()
    sim.run(tfinal=TSTOP * U.ms, dt=DT * U.ms)
    run_t = time.time() - run_t0

    spikes = sim.spikes()
    n = len(spikes)
    print("RESULT_NCELL=%d RESULT_NE=%d RESULT_NI=%d" % (NCELL, N_E, N_I))
    print("RESULT_GPU=%s RESULT_HAS_GPU=%s" % ("1" if USE_GPU else "0", ctx.has_gpu))
    print("RESULT_FANIN=%d" % int(CONNECTIVITY * NCELL))
    print("RESULT_BUILD_S=%.3f" % build_t)
    print("RESULT_RUN_S=%.3f" % run_t)
    print("RESULT_WALL_S=%.3f" % (build_t + run_t))
    print("RESULT_SPIKES=%d" % n)
    print("RESULT_RATE_HZ=%.4f" % (n / NCELL / (TSTOP / 1000.0)))


if __name__ == "__main__":
    main()
