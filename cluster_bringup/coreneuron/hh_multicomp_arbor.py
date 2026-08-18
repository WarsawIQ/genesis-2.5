#!/usr/bin/env python3
"""The GENESIS multi-compartment benchmark, rebuilt in Arbor.

Third implementation of the same model, after GENESIS
(hh_multicompartment_createmap.g) and NEURON (hh_multicomp_neuron.py). Arbor is
the one competitor whose GPU backend is reachable on this cluster -- it targets
CUDA directly, where CoreNEURON offloads through OpenACC and needs NVIDIA's
compilers -- so this is what makes a GPU-to-GPU comparison possible.

Geometry and properties as in the other two:
    soma        20 um long, 20 um diameter
    dendrite    50 um long, 2 um diameter, 15 in a chain
    cm          0.01 F/m2, rL 30 ohm cm
    pas         g = 1/3333.33 S/cm2, e = -59.387 mV
    hh          gnabar 0.12, gkbar 0.036 S/cm2, gl 0 (leak is in pas)
    iclamp      0.5 nA at the soma, on throughout
    dt          0.01 ms

One control volume per segment reproduces the 16 compartments the other two
simulators integrate, so the per-step work matches.
"""

import os
import sys
import time

import arbor as A
from arbor import units as U

N = int(sys.argv[1]) if len(sys.argv) > 1 else 100
STEPS = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
NCOMP = int(os.environ.get("BENCH_NCOMP", "16"))
USE_GPU = os.environ.get("USE_GPU", "0") == "1"
TRACE = os.environ.get("TRACE", "0") == "1"
TRACE_CSV = os.environ.get("TRACE_CSV", "arbor_vm.csv")
# See the note in hh_multicomp_neuron.py: zero injection gives a quiescent cell
# at the same per-step cost, which is the control for the firing-rate objection.
INJECT_NA = float(os.environ.get("INJECT_NA", "0.5"))
DT = 0.01

# Tag 1 is the soma, tag 2 the dendrites (see make_cell). Naming the region and
# placing at its centre makes the injection site independent of how Arbor
# happens to decompose the morphology into branches.
LABELS = A.label_dict({'soma': '(tag 1)', 'dend': '(tag 2)'})
SOMA_CENTRE = '(on-components 0.5 (region "soma"))'
# The far probe must sit where the other two simulators read: NEURON samples
# secs[NCOMP-1](0.5) and GENESIS reports compartment NCOMP-1, both the centre of
# the last dendrite, not the cable's end. With one CV per segment that centre is
# the CV centre, so the probe returns the CV value rather than an interpolation.
_LEN = 20.0 + (NCOMP - 1) * 50.0
TIP = '(location 0 %.10f)' % ((20.0 + (NCOMP - 1 - 0.5) * 50.0) / _LEN)


def make_cell():
    tree = A.segment_tree()
    # soma, then NCOMP-1 dendrite segments end to end
    prox = A.mpoint(0, 0, 0, 10.0)
    dist = A.mpoint(20, 0, 0, 10.0)
    p = tree.append(A.mnpos, prox, dist, tag=1)
    x = 20.0
    for _ in range(NCOMP - 1):
        p = tree.append(p, A.mpoint(x, 0, 0, 1.0), A.mpoint(x + 50.0, 0, 0, 1.0), tag=2)
        x += 50.0

    decor = A.decor()
    decor.set_property(Vm=-70.0 * U.mV, cm=0.01 * U.F / U.m2, rL=30.0 * U.Ohm * U.cm)
    decor.paint('(all)', A.density('pas/e=-59.387', {'g': 1.0 / 3333.33}))
    decor.paint('(all)', A.density('hh', {'gnabar': 0.12, 'gkbar': 0.036, 'gl': 0.0}))
    # Arbor's neuron_cable_properties() supplies NEURON's default reversal
    # potentials (na +50, k -77), but this model does not use them: GENESIS
    # derives ENa = EREST+115 mV and EK = EREST-12 mV from the 1952 paper, and
    # the NEURON arm sets s.ena/s.ek to match. Without these two lines Arbor
    # integrates a different cell and fires several times faster.
    decor.set_ion('na', rev_pot=45.0 * U.mV)
    decor.set_ion('k', rev_pot=-82.0 * U.mV)
    # The cable is unbranched, so Arbor makes the whole 770 um cell one branch
    # and '(location 0 0.5)' is 385 um from the root -- the middle of the
    # dendrite, not the soma. NEURON injects at secs[0](0.5) and GENESIS into
    # compartment 0, both the soma, so the injection is placed by region here
    # rather than by a relative position along the branch.
    decor.place(SOMA_CENTRE, A.iclamp(0.0 * U.ms, 1e9 * U.ms, INJECT_NA * U.nA), 'ic')
    if TRACE:
        decor.place(SOMA_CENTRE, A.threshold_detector(-20.0 * U.mV), 'det')
    # One CV per segment: the 16 compartments the other simulators use.
    decor.discretization(A.cv_policy_every_segment())
    return A.cable_cell(A.morphology(tree), decor, LABELS)


class Bench(A.recipe):
    def __init__(self, n):
        A.recipe.__init__(self)
        self.n = n
        self.cell = make_cell()
        self.props = A.neuron_cable_properties()
        self.props.catalogue = A.default_catalogue()

    def num_cells(self):
        return self.n

    def cell_kind(self, gid):
        return A.cell_kind.cable

    def cell_description(self, gid):
        return self.cell

    def global_properties(self, kind):
        return self.props

    def connections_on(self, gid):
        return []

    def event_generators(self, gid):
        return []

    def probes(self, gid):
        if TRACE and gid == 0:
            return [A.cable_probe_membrane_voltage(SOMA_CENTRE, "soma"),
                    A.cable_probe_membrane_voltage(TIP, "far")]
        return []


build_t0 = time.time()
recipe = Bench(N)
ctx = A.context(gpu_id=0) if USE_GPU else A.context()
hint = A.partition_hint()
hint.prefer_gpu = USE_GPU
decomp = A.partition_load_balance(recipe, ctx)
sim = A.simulation(recipe, ctx, decomp)
build_t = time.time() - build_t0

if TRACE:
    sim.record(A.spike_recording.all)
    h_soma = sim.sample((0, "soma"), A.regular_schedule(DT * U.ms))
    h_far = sim.sample((0, "far"), A.regular_schedule(DT * U.ms))

run_t0 = time.time()
sim.run(tfinal=STEPS * DT * U.ms, dt=DT * U.ms)
run_t = time.time() - run_t0

if TRACE:
    (d_soma, _), = sim.samples(h_soma)
    (d_far, _), = sim.samples(h_far)
    with open(TRACE_CSV, "w") as fh:
        fh.write("t_ms,vm_soma_mV,vm_far_mV\n")
        for (t, vs), (_, vf) in zip(d_soma, d_far):
            fh.write("%.5f,%.6f,%.6f\n" % (t, vs, vf))
    nspk = sum(1 for s in sim.spikes() if s[0][0] == 0)
    print("RESULT_TRACE_CSV=%s" % TRACE_CSV)
    print("RESULT_TRACE_SAMPLES=%d" % len(d_soma))
    print("RESULT_SPIKES_CELL0=%d" % nspk)
    print("RESULT_RATE_HZ=%.4f" % (nspk / (STEPS * DT / 1000.0)))
    print("RESULT_VM_SOMA=%.6f" % d_soma[-1][1])
    print("RESULT_VM_FAR=%.6f" % d_far[-1][1])

print(f"RESULT_N={N} RESULT_NCOMP={NCOMP} RESULT_TOTAL_COMPS={N * NCOMP} RESULT_STEPS={STEPS}")
print(f"RESULT_GPU={'1' if USE_GPU else '0'} RESULT_HAS_GPU={ctx.has_gpu}")
print(f"RESULT_CTX={str(ctx).replace(chr(32), '')}")
print(f"RESULT_BUILD_S={build_t:.3f}")
print(f"RESULT_RUN_S={run_t:.3f}")
print(f"RESULT_WALL_S={build_t + run_t:.3f}")
