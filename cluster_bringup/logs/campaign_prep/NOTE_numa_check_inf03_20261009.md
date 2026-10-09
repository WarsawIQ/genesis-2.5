# numa_check on inf03, 2026-10-09

numa_check_inf03_20261009_233224.csv and numa_check_inf03_20261009_233225.csv
are not used: the same job was queued twice by mistake and the two copies ran
at the same time on the node, so their runs competed. The clean run, alone on
the node, is numa_check_inf03_20261009_234440.csv: every NUMA node within 2%
(25.4-25.9 s), unlike inf02, whose GPU socket (nodes 0 and 1) runs the CPU arm
about 18% slower than the other (numa_check_inf02_20261009_231046.csv).
