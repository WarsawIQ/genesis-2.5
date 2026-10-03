#!/usr/bin/env python3
"""Synthetic campaign sessions, for testing the pipeline before the campaign.

    python3 reproduce/tests/fixtures/make_campaign_fixture.py <outdir>

Writes E2, E3, E4, E7, E8 and E3c session CSVs in the harness format
(cluster_bringup/campaign/lib.sh) with OBVIOUSLY SYNTHETIC values: straight
lines with a seeded +-3% jitter, chosen so the figures have a shape and the
staged claims have known expected values (asserted in
reproduce/tests/test_campaign_claims.sh):

    e2_max_e2e_a40 = 62.5     e2_max_e2e_a100 = 83.3
    e2_fp64_cost_a40 = 1.30   e4_crossover_k_a40 = 1000 (fp64: 4000)
    e7_inter_over_uniform = 1.30, block 1.05, cpu control 1.00
    e8 tree gain at K=5000 = 5%, spiking gain = 0.42%
    e3c exponent = 1.00, construction_1700k_s = 10.0

Used by test_campaign_plots.sh and test_campaign_claims.sh; never by anything
that produces a published number (the claim map's data live under
cluster_bringup/logs/, and these files exist only inside a test's directory).
"""

import os
import random
import sys

HEAD = ("# experiment: %s\n# session: %s\n"
        "# commit: 0000000000000000000000000000000000000000\n"
        "# node: %s\n# gpu: NVIDIA %s\n")
COLS = "session,experiment,arm,rep,order,wall_s,metric,metric_value,status,started\n"


def write(d, exp, node, gpu, arms):
    s = "%s_20990101_000000" % node
    with open(os.path.join(d, "%s_%s.csv" % (exp, s)), "w") as f:
        f.write(HEAD % (exp, s, node, gpu))
        f.write(COLS)
        for arm, wall, metric in arms:
            f.write("%s,%s,%s,0,1,%.4f,t,%.5f,ok,t0\n" % (s, exp, arm, wall * 1.1, metric))
            for rep in (1, 2, 3):
                j = random.uniform(0.97, 1.03)
                f.write("%s,%s,%s,%d,1,%.4f,t,%.5f,ok,t0\n"
                        % (s, exp, arm, rep, wall * j, metric * j))
            f.write("%s,%s,%s,4,1,0.001,,,rejected: synthetic,t0\n" % (s, exp, arm))


def main(d):
    os.makedirs(d, exist_ok=True)
    random.seed(7)
    for node, gpu, f in (("inf02", "A40", 1.0), ("inf03", "A100", 0.6)):
        write(d, "E2", node, gpu,
              [a for k in (200, 1000, 5000, 10000)
               for a in (("cpu_k%d" % k, 0.02 * k, 0),
                         ("g32_k%d" % k, 1.2 + 0.0002 * k * f, 0),
                         ("g64_k%d" % k, 1.56 + 0.00026 * k * f, 0))])
        write(d, "E3", node, gpu,
              [(p % n, w * n / 1000.0, m * n / 1000.0)
               for n in (1000, 10000, 50000)
               for p, w, m in (("t2_cpu_n%d", 6.0, 5.0), ("t2_cuda_n%d", 1.5 * f, 0.1 * f),
                               ("t2_ocl_n%d", 1.7 * f, 0.12 * f))])
        write(d, "E4", node, gpu,
              [(p % k, a + b * k * f, 0) for k in (1000, 5000, 20000)
               for p, a, b in (("g32_k%d", 1.2, 0.0002), ("g64_k%d", 1.3, 0.0004),
                               ("arb_k%d", 0.9, 0.0005))])
        write(d, "E8", node, gpu,
              [("tree_k5000_g0", 4.2, 0), ("tree_k5000_g1", 4.0, 0),
               ("tree_k50000_g0", 8.24, 0), ("tree_k50000_g1", 8.0, 0),
               ("spk_g0", 48.0, 0), ("spk_g1", 47.8, 0)])
    write(d, "E7", "inf03", "A100",
          [("gpu_uni36", 2.0, 1.0), ("gpu_mix_inter", 2.5, 1.3), ("gpu_mix_block", 2.1, 1.05),
           ("cpu_uni36", 40.0, 5.0), ("cpu_mix_inter", 40.0, 5.0)])
    write(d, "E3c", "inf03", "none",
          [("con_n%d" % n, 1e-4 * n, 0) for n in (1000, 8000, 31000, 100000)])
    print(d)


if __name__ == "__main__":
    main(sys.argv[1])
