// Prototyp Z kanalami i wiadomosciami, potem createmap -- uczciwe porownanie
// z petla SLI benchmarku (ten sam koncowy model).
float EREST_ACT = -0.070
int NCELL = 50000
int NCOMP = 16
create neutral /library
create tabchannel /library/Na_chan
setfield /library/Na_chan Ek 0.045 Xpower 3 Ypower 1
create tabchannel /library/K_chan
setfield /library/K_chan Ek -0.082 Xpower 4
create neutral /library/cell
int c
for (c = 0; c < {NCOMP}; c = c + 1)
    create compartment /library/cell/c{c}
    setfield /library/cell/c{c} dia 2e-6 len 20e-6 Em {EREST_ACT} Rm 1e9 Ra 1e6 Cm 1e-11
    copy /library/Na_chan /library/cell/c{c}/Na_chan
    setfield /library/cell/c{c}/Na_chan Gbar 1e-6
    addmsg /library/cell/c{c}/Na_chan /library/cell/c{c} CHANNEL Gk Ek
    addmsg /library/cell/c{c} /library/cell/c{c}/Na_chan VOLTAGE Vm
    copy /library/K_chan /library/cell/c{c}/K_chan
    setfield /library/cell/c{c}/K_chan Gbar 1e-6
    addmsg /library/cell/c{c}/K_chan /library/cell/c{c} CHANNEL Gk Ek
    addmsg /library/cell/c{c} /library/cell/c{c}/K_chan VOLTAGE Vm
    if (c > 0)
        addmsg /library/cell/c{c-1} /library/cell/c{c} AXIAL previous_state
        addmsg /library/cell/c{c} /library/cell/c{c-1} RAXIAL Ra previous_state
    end
end
create neutral /net
echo "START_CREATEMAP"
createmap /library/cell /net {NCELL} 1 -delta 10e-6 1
echo "END_CREATEMAP"
quit
