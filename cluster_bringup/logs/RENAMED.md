# Data files renamed when they were added to the repository

Some data files were given clearer names when they were copied from the cluster. The
content is byte-identical to the file the run wrote; this table connects the two, so a
cluster log or a script that mentions the original name can be followed here.

| Written on the cluster as | In the repository as |
|---|---|
| `weekend_campaign_inf02_20260816_032225.csv` | `weekend_campaign_inf02_A40_20260816_clean.csv` |
| `weekend_campaign_inf03_20260816_032439.csv` | `weekend_campaign_inf03_A100_20260816_clean.csv` |
| `multicomp_walltime_hh_multicompartment_createmap_inf02_20260816_001425.csv` | `multicomp_walltime_createmap_inf02_A40_clean.csv` |
| `multicomp_walltime_hh_multicompartment_createmap_inf03_20260816_001125.csv` | `multicomp_walltime_createmap_inf03_A100_clean.csv` |
| `multicomp_ksweep_inf02_20260816_124313.csv` | `multicomp_ksweep_inf02_A40_20260816.csv` |
| `crossover_inf03_20260817_161238.csv` | `crossover_inf03_20260817.csv` |

Checked on 2026-09-30 by SHA-256 against the cluster copies. From now on
`cluster_bringup/sync_from_cluster.sh` brings files in under the name the run gave them.
