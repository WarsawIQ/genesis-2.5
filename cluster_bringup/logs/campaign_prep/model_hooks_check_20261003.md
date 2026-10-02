# Model switches for the campaign: checks on a laptop CPU build, 2026-10-03

Binary: nxgenesis_nocl from cluster_bringup/12_build_cpu.sh, built from the working
tree that became the commit adding these switches. CPU solver (chanmode 1).

## hh_multicompartment_createmap.g, switches unset

Old script (HEAD before the change) and new script, N=200, 300 steps, NCOMP=16. The
outputs differ only in line numbers in GENESIS's messages and three added
"CastToInt: Error casting ''" messages for the unset switches (the script already
prints the same message for its other unset variables). Result lines are identical:

    RESULT_VM_FAR= 0.005945634326
    RESULT_VM_SOMA= -0.02321063594
    === done: N= 200  NCOMP= 16  steps= 300  chanmode= 1  ===

## Mixed trees, GENESIS_BENCH_NCOMP_MIX_A=8, _B=64, N=200

    order 0: Total comps: 7200, ncompts: 7200, === done: N= 200  NCOMP= 8,64 ...
    order 1: Total comps: 7200, ncompts: 7200, === done: N= 200  NCOMP= 8,64 ...

Which cells have a 64th compartment ({exists /net/cellI/c63}):

    order 0: cell1 yes, cell99 yes, cell100 no, cell199 yes    (odd cells: 64)
    order 1: cell1 no,  cell99 no,  cell100 yes, cell199 yes   (second half: 64)

N=201 is refused: "ERROR: mixed tree sizes need an even N_NEURONS, got 201".

## GENESIS_VANET2_TMAX

    VAnet2-batch.g         unset: tmax = 0.05, then 4.95 (42 s)   0.2: tmax = 0.05, then 0.2 (3 s)
    VAnet2-batch-1solver.g unset: tmax = 0.05, then 4.95 (27 s)   0.2: tmax = 0.05, then 0.2 (2 s)

With the switches unset the accelerator regression (80_accel_regression.sh, which runs
VAnet2-batch.g) must still pass on both cards; that is part of the freeze gate.
