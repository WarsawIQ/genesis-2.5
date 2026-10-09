#!/usr/bin/env python3
"""Synthetic campaign sessions, for testing the pipeline before the campaign.

    python3 reproduce/tests/fixtures/make_campaign_fixture.py <outdir>

Writes E1, E2, E3, E4, E5, E7, E8 and E3c session CSVs in the harness format
(cluster_bringup/campaign/lib.sh) with OBVIOUSLY SYNTHETIC values: straight
lines with a seeded +-3% jitter, chosen so the figures have a shape and the
staged claims have known expected values (asserted in
reproduce/tests/test_campaign_claims.sh):

    e2_max_e2e_a40 = 62.5     e2_max_e2e_a100 = 83.3
    e2_fp64_cost_a40 = 1.30   e4_crossover_k_a40 = 2000
    e4_fp64_over_arbor_a40 = 31.3/25.6 = 1.22 (fp64 never crosses Arbor)
    e7_inter_over_uniform = 1.30, block 1.05, cpu control 1.00
    e8 tree gain at K=5000 = 5%, spiking gain = 0.42%
    e3c exponent = 1.00, construction_1700k_s = 10.0
    e1: GENESIS 1-solver CPU 35 s; NEURON 2.5x, CoreNEURON GPU 0.7x of it
    e3 Table 1 at N = 50000: CUDA 40x, OpenCL 20x the CPU; trees: CUDA starts
        8 s behind, so it passes the CPU end to end from N = 10000 (regimes)
    e5: CPU 27.0 Hz; first departure g64 2.65 ms, per-cell CPU 2.35 ms;
        seeds 24.0-29.0 Hz, KS 0.020-0.050 (the spike comparison, _spikes.csv)

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


SPK_COLS = ("run,file,spikes,rate_hz,isi_mean_ms,isi_cv,isi_median_ms,isi_p05_ms,"
            "isi_p95_ms,vs,identical,first_divergence_s,spikes_identical_before,"
            "count_diff_pct,ks_isi,cell_count_corr\n")


def spikes_csv(d, exp, node):
    """The table spikes_compare.py writes next to an E5 session."""
    rows = (("cpu_r1", 27.0, "", 0.0, 0.0), ("g32_r1", 27.1, "0.002650", 0.4, 0.002),
            ("g64_r1", 27.4, "0.002650", 1.5, 0.006), ("pcell_r1", 26.6, "0.002350", -1.6, 0.008),
            ("sd1_r1", 29.0, "0.001600", 7.4, 0.030), ("sd2_r1", 25.0, "0.001600", -7.4, 0.020),
            ("sd3_r1", 24.0, "0.001600", -11.1, 0.050), ("sd4_r1", 25.5, "0.001600", -5.6, 0.035))
    with open(os.path.join(d, "%s_%s_20990101_000000_spikes.csv" % (exp, node)), "w") as f:
        f.write(SPK_COLS)
        for run, rate, div, cnt, ks in rows:
            f.write("%s,synthetic,%d,%.4f,30,4,7,5,124,cpu_r1,%s,%s,0,%.4f,%.5f,0.99\n"
                    % (run, rate * 4000 * 10, rate, "yes" if not div else "no", div, cnt, ks))


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
              [(p % n, c + w * n / 1000.0, m * n / 1000.0)
               for n in (1000, 10000, 50000)
               for p, c, w, m in (("t2_cpu_n%d", 0.0, 6.0, 5.0),
                                  ("t2_cuda_n%d", 8.0, 1.5 * f, 0.1 * f),
                                  ("t2_ocl_n%d", 8.0, 1.7 * f, 0.12 * f))]
              + [(p % n, w, 0) for n in (500, 5000, 50000)
                 for p, w in (("t1_cpu_n%d", 0.4 * n), ("t1_cuda_n%d", 0.01 * n),
                              ("t1_ocl_n%d", 0.02 * n))])
        write(d, "E4", node, gpu,
              [(p % k, a + b * k * f, 0) for k in (1000, 5000, 20000, 50000)
               for p, a, b in (("g32_k%d", 1.2, 0.0002), ("g64_k%d", 1.3, 0.0006),
                               ("arb_k%d", 0.6, 0.0005))])
        write(d, "E8", node, gpu,
              [("tree_k5000_g0", 4.2, 0), ("tree_k5000_g1", 4.0, 0),
               ("tree_k50000_g0", 8.24, 0), ("tree_k50000_g1", 8.0, 0),
               ("spk_g0", 48.0, 0), ("spk_g1", 47.8, 0)])
    write(d, "E7", "inf03", "A100",
          [("gpu_uni36", 2.0, 1.0), ("gpu_mix_inter", 2.5, 1.3), ("gpu_mix_block", 2.1, 1.05),
           ("cpu_uni36", 40.0, 5.0), ("cpu_mix_inter", 40.0, 5.0)])
    write(d, "E1", "inf03", "A100",
          [("g_cpu_1s", 35.0, 4000), ("g_cpu_pub", 70.0, 4000), ("g_gpu32_1s", 40.0, 4000),
           ("g_gpu64_1s", 45.0, 4000), ("nrn_cpu", 87.5, 0), ("nrn_cb_cpu", 80.0, 0),
           ("cn_cpu", 70.0, 0), ("cn_gpu", 24.5, 0), ("arbor_gpu", 150.0, 0)])
    write(d, "E5", "inf03", "A100",
          [(a, 90.0, 1.0e6) for a in ("cpu", "g32", "g64", "pcell", "sd1", "sd2", "sd3", "sd4")])
    spikes_csv(d, "E5", "inf03")
    write(d, "E3c", "inf03", "none",
          [("con_n%d" % n, 1e-4 * n, 0) for n in (1000, 8000, 31000, 100000)])
    print(d)


if __name__ == "__main__":
    main(sys.argv[1])
