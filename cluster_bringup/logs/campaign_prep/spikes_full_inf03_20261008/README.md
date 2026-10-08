# Full VAnet2, CPU vs CUDA spike trains (inf03, 2026-10-08)

4000 cells, VAnet2-batch-1solver.g, GENESIS_VANET2_SCALE=0, TMAX=4.95 (5.0 s
simulated), built from 9ec9c33 (the CUDA first-step fix) in a clone on inf03.
Produced by

    SCALE=0 TMAX=4.95 sh cluster_bringup/campaign/spike_start_check.sh

whose log is ../spike_start_inf03_20261008_023709.txt. The spike files are the
GENESIS_VANET2_SPIKEFILE outputs of the cpu, cuda32 and cuda64 arms, gzipped.
compare.csv is

    python3 cluster_bringup/campaign/spikes_compare.py compare.csv 4000 5.0 \
        cpu=cpu.txt.gz cuda64=cuda64.txt.gz cuda32=cuda32.txt.gz

The OpenCL arm is not here: OpenCL refuses networks with synaptic channels and
runs them on the CPU solver, and its spike file was identical to the CPU's
(545371 spikes, see the log).
