// genesis
// Does the accelerator deliver synaptic input, and does it emit spikes?
//
// Two cells. Cell 0 is driven by injected current and fires; its spikegen
// feeds a synchan on cell 1, which has no injection of its own and can only
// fire if the synaptic path works. Run under the CPU and the CUDA binary and
// compare: cell 0's spikes test emission, cell 1's test delivery.
//
// Two driven cells under one hsolve, each with its own spikegen, and a
// spikehistory counting every event. Run the same script under the CPU and
// the CUDA binary: the counts must agree. VAnet2 is far too large to use for
// this question -- it takes tens of minutes just to build under the GPU -- and
// its recurrent synapses mean a wrong answer has several possible causes.
// Here there are no synapses at all, so a mismatch can only be the spike path.
//
// Prepared by Karol Chlasta (karol@chlasta.pl).

float EREST = -0.070
float DT    = 10e-6
int   NSTEP = 20000
int e_ns = {getenv GENESIS_BENCH_NSTEP}
if ({e_ns} >= 1)
    NSTEP = {e_ns}
end

include genesis/src/startup/schedule.g

create neutral /library
pushe /library
create compartment soma
setfield soma Em {EREST} initVm {EREST} Rm 3.3e8 Cm 1e-10 \
    Ra 1e6 dia 20e-6 len 20e-6 inject 0.5e-9
create tabchannel Na_chan
setfield Na_chan Ek 0.045 Xpower 3 Ypower 1 Zpower 0
setupalpha Na_chan X {100000.0*(0.025+EREST)} -100000.0 -1.0 \
    {-1.0*(0.025+EREST)} -0.01 4000.0 0.0 0.0 {0.0-EREST} 0.018
setupalpha Na_chan Y 70.0 0.0 0.0 {0.0-EREST} 0.02 \
    1000.0 0.0 1.0 {-0.03-EREST} -0.01
create tabchannel K_chan
setfield K_chan Ek -0.082 Xpower 4 Ypower 0 Zpower 0
setupalpha K_chan X {10000.0*(0.010+EREST)} -10000.0 -1.0 \
    {-1.0*(0.010+EREST)} -0.01 125.0 0.0 0.0 {0.0-EREST} 0.08
create spikegen spike
setfield spike thresh 0.0 abs_refract 10e-3 output_amp 1
create synchan syn
setfield syn Ek 0.045 tau1 1e-3 tau2 2e-3 gmax 2e-7
pope
disable /library

create neutral /net
int i
str cell
for (i = 0; i < 2; i = i + 1)
    cell = "/net/cell" @ {i}
    create neutral {cell}
    copy /library/soma {cell}/soma
    copy /library/Na_chan {cell}/soma/Na_chan
    setfield {cell}/soma/Na_chan Gbar 1.5e-6
    addmsg {cell}/soma/Na_chan {cell}/soma CHANNEL Gk Ek
    addmsg {cell}/soma {cell}/soma/Na_chan VOLTAGE Vm
    copy /library/K_chan {cell}/soma/K_chan
    setfield {cell}/soma/K_chan Gbar 4.5e-7
    addmsg {cell}/soma/K_chan {cell}/soma CHANNEL Gk Ek
    addmsg {cell}/soma {cell}/soma/K_chan VOLTAGE Vm
    copy /library/spike {cell}/soma/spike
    addmsg {cell}/soma {cell}/soma/spike INPUT Vm
    // cell 1 is undriven and carries the synapse: it fires only if the
    // accelerator delivers synaptic activation.
    if ({i} == 1)
        setfield {cell}/soma inject 0.0
        copy /library/syn {cell}/soma/syn
        addmsg {cell}/soma/syn {cell}/soma CHANNEL Gk Ek
        addmsg {cell}/soma {cell}/soma/syn VOLTAGE Vm
        addmsg /net/cell0/soma/spike {cell}/soma/syn SPIKE
        setfield {cell}/soma/syn synapse[0].weight 1.0 synapse[0].delay 0.0
    end
end

create spikehistory /spikeout
setfield /spikeout filename "spikegen_syn_check.txt" leave_open 1 ident_toggle 0
for (i = 0; i < 2; i = i + 1)
    addmsg /net/cell{i}/soma/spike /spikeout SPIKESAVE
end

setclock 0 {DT}
useclock /net/##[] 0
useclock /spikeout 0

create hsolve /net/solver
setfield /net/solver path "/net/##[][TYPE=compartment]" \
    chanmode {getenv GENESIS_BENCH_CHANMODE} calcmode 1
call /net/solver SETUP
useclock /net/solver 0

reset
step {NSTEP}
call /net/solver HGET /net/cell0/soma
call /net/solver HGET /net/cell1/soma
echo "RESULT_VM0= " {getfield /net/cell0/soma Vm}
echo "RESULT_VM1= " {getfield /net/cell1/soma Vm}
echo "DONE steps=" {NSTEP}
quit
