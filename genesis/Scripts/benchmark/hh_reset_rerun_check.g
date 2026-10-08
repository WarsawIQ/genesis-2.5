// genesis
//
// RESET must return the accelerator to the same state as the CPU solver.
//
// N driven single-compartment HH cells under one hsolve (chanmode 4). Runs
// N_STEPS, records cell0's Vm, RESETs, runs N_STEPS again and records it once
// more. Both runs start from the same reset state, so on any backend the two
// voltages must be equal; on the CPU they always were. Before 2026-10-08 the
// CUDA backend kept its own copies of vm and of the gating state across RESET
// (and never uploaded vm at all when it also did the solve), so the second
// run started from where the first had ended.
//
//   nxgenesis -nosimrc -notty -batch hh_reset_rerun_check.g [N] [N_STEPS]
//
// Prints RESET_RERUN: SAME or DIFFERENT, and both voltages.

int   N_NEURONS = 8
int   N_STEPS   = 300
if ({argc} > 0)
    N_NEURONS = {argv 1}
end
if ({argc} > 1)
    N_STEPS = {argv 2}
end
float DT        = 10e-6
float PI        = 3.141592653589793
float EREST_ACT = -0.070
float SOMA_L    = 20e-6
float SOMA_D    = 20e-6

include genesis/src/startup/schedule.g

create neutral /library
pushe /library
create tabchannel Na_chan
setfield Na_chan Ek {EREST_ACT + 0.115} Ik 0 Gk 0 Xpower 3 Ypower 1 Zpower 0
setupalpha Na_chan X \
    {100000.0 * (0.025 + EREST_ACT)} -100000.0 -1.0 {-1.0 * (0.025 + EREST_ACT)} -0.01 \
    4000.0 0.0 0.0 {0.0 - EREST_ACT} 0.018
setupalpha Na_chan Y \
    70.0 0.0 0.0 {0.0 - EREST_ACT} 0.02 \
    1000.0 0.0 1.0 {-0.03 - EREST_ACT} -0.01
create tabchannel K_chan
setfield K_chan Ek {EREST_ACT - 0.012} Ik 0 Gk 0 Xpower 4 Ypower 0 Zpower 0
setupalpha K_chan X \
    {10000.0 * (0.010 + EREST_ACT)} -10000.0 -1.0 {-1.0 * (0.010 + EREST_ACT)} -0.01 \
    125.0 0.0 0.0 {0.0 - EREST_ACT} 0.08
pope
disable /library

float area = SOMA_L * PI * SOMA_D
create neutral /net
int n
str cell
for (n = 0; n < {N_NEURONS}; n = n + 1)
    cell = "/net/cell" @ {n}
    create neutral {cell}
    create compartment {cell}/soma
    setfield {cell}/soma Em {EREST_ACT + 0.010613} initVm {EREST_ACT} inject 2e-9 \
        Rm {0.333333 / area} Cm {0.01 * area} Ra {0.3 * SOMA_L / (PI * SOMA_D * SOMA_D / 4)}
    copy /library/Na_chan {cell}/soma/Na_chan
    setfield {cell}/soma/Na_chan Gbar {1200.0 * area}
    addmsg {cell}/soma/Na_chan {cell}/soma CHANNEL Gk Ek
    addmsg {cell}/soma {cell}/soma/Na_chan VOLTAGE Vm
    copy /library/K_chan {cell}/soma/K_chan
    setfield {cell}/soma/K_chan Gbar {360.0 * area}
    addmsg {cell}/soma/K_chan {cell}/soma CHANNEL Gk Ek
    addmsg {cell}/soma {cell}/soma/K_chan VOLTAGE Vm
end
setclock 0 {DT}
useclock /net/##[] 0
create hsolve /net/solver
setfield /net/solver path "/net/##[][TYPE=compartment]" chanmode 4 calcmode 1
call /net/solver SETUP
useclock /net/solver 0

reset
step {N_STEPS}
call /net/solver HGET /net/cell0/soma
float vm1 = {getfield /net/cell0/soma Vm}

reset
step {N_STEPS}
call /net/solver HGET /net/cell0/soma
float vm2 = {getfield /net/cell0/soma Vm}

echo "RESET_RERUN_VM1=" {vm1}
echo "RESET_RERUN_VM2=" {vm2}
if ({abs {{vm1} - {vm2}}} < 1e-12)
    echo "RESET_RERUN: SAME"
else
    echo "RESET_RERUN: DIFFERENT"
end
quit
