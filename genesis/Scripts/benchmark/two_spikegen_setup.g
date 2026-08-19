// genesis
// Two cells, one hsolve, one spikegen each.
//
// GENESIS has always refused a second spikegen in a solver (hines_child.c:
// "second spikegen ... not allowed"). That refusal is what forces a spiking
// network to be built as one solver per cell, which is why the accelerator
// cannot pay for itself there -- VAnet2 ends up with 4000 solvers and 4000
// dispatches per step. This is the smallest model that provokes it.
//
// The spikegen hangs off the compartment, not off the cell: hines_child.c
// walks compt->child when it classifies children, and VAnet2 does the same
// (planarconnect addresses /Ex_layer/Ex_cell[]/soma/spike). A spikegen placed
// as a sibling of the soma is never seen by SETUP, so the test would pass for
// the wrong reason.
//
// Prints SETUP_OK then STEP_OK. On the unmodified tree it reaches neither:
// SETUP raises the refusal and returns an error.
//
// Prepared by Karol Chlasta (karol@chlasta.pl).

float EREST = -0.070
float DT    = 10e-6

include genesis/src/startup/schedule.g

create neutral /library
pushe /library
create compartment soma
setfield soma Em {EREST} initVm {EREST} Rm 1e8 Cm 1e-10 Ra 1e6 \
    dia 20e-6 len 20e-6
create spikegen spike
setfield spike thresh 0.0 abs_refract 10e-3 output_amp 1
pope
disable /library

create neutral /net
int i
str cell
for (i = 0; i < 2; i = i + 1)
    cell = "/net/cell" @ {i}
    create neutral {cell}
    copy /library/soma {cell}/soma
    copy /library/spike {cell}/soma/spike
    addmsg {cell}/soma {cell}/soma/spike INPUT Vm
end

setclock 0 {DT}
useclock /net/##[] 0

create hsolve /net/solver
// chanmode 4, not 1: below chanmode 2 the solver does not absorb the
// compartment's children at all, so the spikegens are never classified and
// the refusal this test exists to provoke never fires. VAnet2 uses 4, and 4
// is the mode the accelerator runs in.
setfield /net/solver path "/net/##[][TYPE=compartment]" chanmode 4 calcmode 1
call /net/solver SETUP
useclock /net/solver 0

echo "SETUP_OK ncompts=" {getfield /net/solver ncompts}
reset
step 10
echo "STEP_OK"
quit
