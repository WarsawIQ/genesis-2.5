// genesis
// HH multicompartment benchmark — N neurons, each a linear cable of NCOMP
// Hodgkin-Huxley compartments (Na + K on every compartment), one hsolve over all.
//
// This is the COMPUTE-BOUND workload class where GPU acceleration is meaningful
// (cf. Arbor ~200x/GPU, NeuroGPU). Unlike the single-compartment squid benchmark,
// the per-step Hines tree solve scales with total compartments = N * NCOMP.
//
// Args:  [N_NEURONS] [N_STEPS] [NCOMP]
// Env:   GENESIS_BENCH_CHANMODE  (1 = CPU Hines reference; 4 = accelerator/GPU, default)
//        GENESIS_CUDA_MULTILOOP=<N_STEPS>  for the CUDA multiloop GPU arm
//
// Prepared by Karol Chlasta (karol@chlasta.pl).

int   N_NEURONS = 1000
int   N_STEPS   = 5000
int   NCOMP     = 16
float DT        = 10e-6
float INJECT    = 0.5e-9

float PI        = 3.141592653589793
float EREST_ACT = -0.070
float CM_DENS   = 0.01
float RM_DENS   = 0.333333
float RA_DENS   = 0.3
float GNA_DENS  = 1200.0
float GK_DENS   = 360.0
float ENA       = {EREST_ACT + 0.115}
float EK        = {EREST_ACT - 0.012}
float ELEAK     = {EREST_ACT + 0.010613}
// soma (comp0) and dendrite (comp1..) geometry
float SOMA_L = 20e-6
float SOMA_D = 20e-6
float DEND_L = 50e-6
float DEND_D = 2e-6

// argv i is valid for i in 1..argc, so the guard for argv i is (argc > i-1).
if ({argc} > 0)
    N_NEURONS = {argv 1}
end
if ({argc} > 1)
    N_STEPS = {argv 2}
end

// NCOMP and CHANMODE via environment (robust: getenv of an unset var casts to 0,
// which is < 1, so we fall back to the defaults). Runner always sets them.
int e_ncomp = {getenv GENESIS_BENCH_NCOMP}
if ({e_ncomp} >= 1)
    NCOMP = {e_ncomp}
end
int CHANMODE = 4
int e_cm = {getenv GENESIS_BENCH_CHANMODE}
if ({e_cm} >= 1)
    CHANMODE = {e_cm}
end

// Control for the firing-rate objection: a quiescent cell costs the same per
// step as a firing one on this model, since there are no synapses or events.
// getenv of an unset variable casts to 0 here, so "unset" cannot mean "zero
// current" -- silencing the cell needs its own flag, and the default is
// untouched by both.
int e_inj = {getenv GENESIS_BENCH_INJECT_PA}
if ({e_inj} >= 1)
    INJECT = {e_inj * 1e-12}
end
if ({getenv GENESIS_BENCH_NOINJECT} >= 1)
    INJECT = 0.0
end

echo "=== HH Multicompartment Benchmark ==="
echo "Neurons:   " {N_NEURONS}
echo "Comp/neuron:" {NCOMP}
echo "Total comps:" {N_NEURONS * NCOMP}
echo "Steps:     " {N_STEPS}
echo "chanmode:  " {CHANMODE}
echo ""

include genesis/src/startup/schedule.g

// ---- channel prototypes (H&H 1952, SI rational-function form) ----
create neutral /library
pushe /library
create tabchannel Na_chan
setfield Na_chan Ek {ENA} Ik 0 Gk 0 Xpower 3 Ypower 1 Zpower 0
setupalpha Na_chan X \
    {100000.0 * (0.025 + EREST_ACT)} -100000.0 -1.0 {-1.0 * (0.025 + EREST_ACT)} -0.01 \
    4000.0 0.0 0.0 {0.0 - EREST_ACT} 0.018
setupalpha Na_chan Y \
    70.0 0.0 0.0 {0.0 - EREST_ACT} 0.02 \
    1000.0 0.0 1.0 {-0.03 - EREST_ACT} -0.01
create tabchannel K_chan
setfield K_chan Ek {EK} Ik 0 Gk 0 Xpower 4 Ypower 0 Zpower 0
setupalpha K_chan X \
    {10000.0 * (0.010 + EREST_ACT)} -10000.0 -1.0 {-1.0 * (0.010 + EREST_ACT)} -0.01 \
    125.0 0.0 0.0 {0.0 - EREST_ACT} 0.08
pope
disable /library

// ---- geometry-derived passive params ----
float soma_area  = SOMA_L * PI * SOMA_D
float soma_xarea = PI * (SOMA_D/2) * (SOMA_D/2)
float dend_area  = DEND_L * PI * DEND_D
float dend_xarea = PI * (DEND_D/2) * (DEND_D/2)

create neutral /net
int c
str comp, prev

// ---- ONE prototype cell, then createmap ----
//
// The model is identical to the explicit-loop version in
// hh_multicompartment_benchmark.g: same geometry, same channels on every
// compartment, same axial coupling. What differs is how the population is
// built. The loop version issues roughly eleven SLI commands per compartment,
// so at 50,000 x 16 that is ~8.8 million interpreted commands and the run is
// dominated by interpreter and path-string overhead rather than by anything
// the simulator does. createmap builds the population in one C-side call from
// a single prototype, which is how the bundled published network model
// (Scripts/VAnet2, Vogels-Abbott) constructs its layers.
//
// Measured on the UMCS A40, 50,000 x 16 compartments: ~37 s the loop way,
// 1.4 s this way. Reporting accelerator speedups against the loop version
// measures the SLI interpreter more than the backend.

create neutral /library/cell
pushe /library/cell
// carea is the compartment's own surface area. Gbar used to be computed from
// soma_area for every compartment, which gave each dendrite four times the
// intended channel density (soma_area / dend_area = 4). Rm and Cm below always
// used the right area, so the intent was never in doubt. Found 2026-08-18 by
// comparing Vm against the NEURON and Arbor implementations of this model.
float carea
for (c = 0; c < {NCOMP}; c = c + 1)
    comp = "/library/cell/c" @ {c}
    create compartment {comp}
    if ({c} == 0)
        setfield {comp} Em {ELEAK} initVm {EREST_ACT} inject {INJECT} \
            Rm {RM_DENS / soma_area} Cm {CM_DENS * soma_area} \
            Ra {RA_DENS * SOMA_L / soma_xarea}
        setfield {comp} dia {SOMA_D} len {SOMA_L}
        carea = {soma_area}
    else
        setfield {comp} Em {ELEAK} initVm {EREST_ACT} \
            Rm {RM_DENS / dend_area} Cm {CM_DENS * dend_area} \
            Ra {RA_DENS * DEND_L / dend_xarea}
        setfield {comp} dia {DEND_D} len {DEND_L}
        carea = {dend_area}
    end
    copy /library/Na_chan {comp}/Na_chan
    setfield {comp}/Na_chan Gbar {GNA_DENS * {carea}}
    addmsg {comp}/Na_chan {comp} CHANNEL Gk Ek
    addmsg {comp} {comp}/Na_chan VOLTAGE Vm
    copy /library/K_chan {comp}/K_chan
    setfield {comp}/K_chan Gbar {GK_DENS * {carea}}
    addmsg {comp}/K_chan {comp} CHANNEL Gk Ek
    addmsg {comp} {comp}/K_chan VOLTAGE Vm
    if ({c} > 0)
        prev = "/library/cell/c" @ {c - 1}
        addmsg {prev} {comp} AXIAL Vm
        addmsg {comp} {prev} RAXIAL Ra Vm
    end
end
pope

echo "Building cables via createmap..."
createmap /library/cell /net {N_NEURONS} 1 -delta 10e-6 1

setclock 0 {DT}
useclock /net/##[] 0

echo "Configuring single hsolve (chanmode=" {CHANMODE} ", N*NCOMP=" {N_NEURONS * NCOMP} " comps)..."
create hsolve /net/solver
setfield /net/solver path "/net/##[][TYPE=compartment]" chanmode {CHANMODE} calcmode 1
call /net/solver SETUP
useclock /net/solver 0
echo "ncompts: " {getfield /net/solver ncompts}

reset

// ---------------------------------------------------------------------------
// Trace tail. Everything above is hh_multicompartment_createmap.g verbatim, so
// the model is the same one the timing benchmark builds; only what happens
// after `reset` differs. This script is never used for timings.
//
// Why a trace at all: the cross-simulator comparison (Table 7) matches the
// three implementations on geometry, conductances, injection and timestep, but
// that is an argument, not a measurement. This emits Vm per step so the three
// can be held against each other numerically.
//
// Two compartments are reported. c0 carries the injection; c{NCOMP-1} is the
// far end of the cable and only moves if axial coupling is integrated, which
// is the part hines_tree_eliminate takes over on the GPU.
//
// HGET before every read: in chanmode 4/5 getfield returns the element's own
// field storage, which the accelerator does not sync each step. Harmless on
// CPU, required on GPU. See the note in hh_multicompartment_createmap.g.

str farcomp = "/net/cell[0]/c" @ {NCOMP - 1}
int i

echo "TRACE_BEGIN dt=" {DT} " ncomp=" {NCOMP} " chanmode=" {CHANMODE}
echo "TRACE_HEADER step t_ms vm_soma_mV vm_far_mV"

for (i = 1; i <= {N_STEPS}; i = i + 1)
    step 1
    // HGET is rejected below chanmode 2, where the element fields are already
    // the solver's own storage and need no pull-back. Calling it anyway costs
    // two errors per step and GENESIS aborts the script at ten.
    if ({CHANMODE} >= 2)
        call /net/solver HGET /net/cell[0]/c0
        call /net/solver HGET {farcomp}
    end
    echo "TRACE " {i} " " {i * DT * 1000.0} " " \
         {{getfield /net/cell[0]/c0 Vm} * 1000.0} " " \
         {{getfield {farcomp} Vm} * 1000.0}
end

echo "TRACE_END"
quit
