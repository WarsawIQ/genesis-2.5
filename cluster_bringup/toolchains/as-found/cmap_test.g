// Czy createmap buduje te sama liczbe elementow taniej niz petla SLI?
int NCELL = 50000
int NCOMP = 16
create neutral /library
create neutral /library/cell
int c
for (c = 0; c < {NCOMP}; c = c + 1)
    create compartment /library/cell/c{c}
    setfield /library/cell/c{c} dia 2e-6 len 20e-6 Em -0.07 Rm 1e9 Ra 1e6 Cm 1e-11
end
create neutral /net
echo "start createmap"
createmap /library/cell /net {NCELL} 1 -delta 10e-6 1
echo "done"
quit
